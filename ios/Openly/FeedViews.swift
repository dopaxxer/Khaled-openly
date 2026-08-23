import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var session: AppSession
    @State private var posts: [Post] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if posts.isEmpty && isLoading {
                    VStack(spacing: 18) {
                        ForEach(0..<3, id: \.self) { _ in FeedSkeletonRow() }
                    }
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else if posts.isEmpty {
                    VStack(spacing: 16) {
                        EmptyState(
                            icon: "text.bubble",
                            title: errorMessage == nil ? "لا توجد منشورات بعد" : "تعذر تحميل المنشورات",
                            message: errorMessage ?? "كن أول من يكتب."
                        )
                        if errorMessage != nil {
                            Button("المحاولة مجددًا") { Task { await load(reset: true) } }
                                .buttonStyle(OpenlySecondaryButtonStyle())
                        }
                    }
                } else {
                    List {
                        ForEach(posts) { post in
                            PostCard(post: post)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(OpenlyTheme.surface)
                                .onAppear {
                                    if post.id == posts.last?.id, nextCursor != nil {
                                        Task { await load(reset: false) }
                                    }
                                }
                        }
                        if isLoading {
                            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                                .padding(.vertical, 18)
                                .listRowSeparator(.hidden)
                                .listRowBackground(OpenlyTheme.surface)
                        } else if nextCursor == nil {
                            Text("هذه كل المنشورات المتاحة.")
                                .font(.system(size: 11))
                                .foregroundColor(OpenlyTheme.subtle)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .listRowSeparator(.hidden)
                                .listRowBackground(OpenlyTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(OpenlyTheme.surface)
                    .refreshable { await load(reset: true) }
                }
            }
            .background(OpenlyTheme.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandLockup(markSize: 28)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if session.user != nil {
                        NavigationLink(destination: NotificationsView()) {
                            Image(systemName: "bell")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(OpenlyTheme.muted)
                                .frame(width: 34, height: 34)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let user = session.user {
                        NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                            IdentityBadge(code: user.publicCode, color: user.identityColor)
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(OpenlyTheme.line, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: LoginView()) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17))
                                .foregroundColor(OpenlyTheme.muted)
                                .frame(width: 34, height: 34)
                        }
                    }
                }
            }
            .task { if posts.isEmpty { await load(reset: true) } }
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset {
            nextCursor = nil
            errorMessage = nil
        }
        do {
            let response = try await session.api.feed(cursor: reset ? nil : nextCursor)
            posts = reset ? response.items : posts + response.items.filter { item in
                !posts.contains(where: { $0.id == item.id })
            }
            nextCursor = response.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct FeedSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(OpenlyTheme.surfaceSoft).frame(width: 110, height: 12)
            RoundedRectangle(cornerRadius: 3).fill(OpenlyTheme.surfaceSoft).frame(height: 15)
            RoundedRectangle(cornerRadius: 3).fill(OpenlyTheme.surfaceSoft).frame(width: 230, height: 15)
            RoundedRectangle(cornerRadius: 3).fill(OpenlyTheme.surfaceSoft).frame(width: 170, height: 11)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenlyTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }
}

struct OpenlySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(OpenlyTheme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PostCard: View {
    @EnvironmentObject private var session: AppSession
    let post: Post
    @State private var engagement: Engagement?
    @State private var isChanging = false
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let code = post.authorCode {
                    NavigationLink(destination: UserProfileView(code: code)) {
                        IdentityBadge(code: code, color: post.authorColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    IdentityBadge(code: "OPENLY", color: post.authorColor)
                }
                Spacer()
                Text(OpenlyDate.relative(post.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(OpenlyTheme.subtle)
            }

            NavigationLink(destination: PostDetailView(postID: post.id)) {
                Text(post.body)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.primary)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            HStack(spacing: 18) {
                NavigationLink(destination: PostDetailView(postID: post.id)) {
                    actionLabel(
                        icon: "bubble.left",
                        text: (post.commentCount ?? 0) > 0 ? "\(post.commentCount ?? 0) تعليق" : "تعليق",
                        active: false
                    )
                }
                .buttonStyle(.plain)

                Button { Task { await toggleLike() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasLiked == true ? "heart.fill" : "heart",
                        text: (engagement?.likeCount ?? 0) > 0 ? "\(engagement?.likeCount ?? 0)" : "إعجاب",
                        active: engagement?.viewerHasLiked == true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChanging)

                Button { Task { await toggleBookmark() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasBookmarked == true ? "bookmark.fill" : "bookmark",
                        text: engagement?.viewerHasBookmarked == true ? "محفوظ" : "حفظ",
                        active: engagement?.viewerHasBookmarked == true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChanging)

                Spacer(minLength: 0)

                Button { showReport = true } label: {
                    actionLabel(icon: "flag", text: "إبلاغ", active: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(OpenlyTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
        .task { await loadEngagement() }
        .sheet(isPresented: $showReport) { ReportView(postID: post.id) }
    }

    private func actionLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
            Text(text)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
        }
        .foregroundColor(active ? OpenlyTheme.accent : OpenlyTheme.muted)
    }

    @MainActor
    private func loadEngagement() async {
        engagement = try? await session.api.engagements(ids: [post.id]).first
    }

    @MainActor
    private func toggleLike() async {
        guard session.requireLogin() else { return }
        let next = !(engagement?.viewerHasLiked ?? false)
        isChanging = true
        do {
            try await session.api.setLike(postID: post.id, enabled: next)
            await loadEngagement()
        } catch { session.alertMessage = error.localizedDescription }
        isChanging = false
    }

    @MainActor
    private func toggleBookmark() async {
        guard session.requireLogin() else { return }
        let next = !(engagement?.viewerHasBookmarked ?? false)
        isChanging = true
        do {
            try await session.api.setBookmark(postID: post.id, enabled: next)
            await loadEngagement()
        } catch { session.alertMessage = error.localizedDescription }
        isChanging = false
    }
}

struct ComposerView: View {
    @EnvironmentObject private var session: AppSession
    @State private var bodyText = ""
    @State private var isPublishing = false
    @FocusState private var isFocused: Bool
    let onPublished: () -> Void

    var body: some View {
        NavigationView {
            Group {
                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لكتابة منشور جديد.")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ScreenHeader("منشور جديد", subtitle: "سيظهر كلامك للجميع بهويتك الملوّنة.")
                        TextEditor(text: $bodyText)
                            .focused($isFocused)
                            .font(.body)
                            .padding(10)
                            .frame(minHeight: 220)
                            .background(OpenlyTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(OpenlyTheme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal)
                            .onChange(of: bodyText) { value in
                                if value.count > 3000 { bodyText = String(value.prefix(3000)) }
                            }

                        HStack {
                            Text("\(bodyText.count) / 3000")
                                .font(.caption)
                                .foregroundColor(OpenlyTheme.muted)
                            Spacer()
                            Button {
                                Task { await publish() }
                            } label: {
                                if isPublishing {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("نشر", systemImage: "paperplane.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.primary)
                            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                        }
                        .padding(.horizontal)
                        Spacer()
                    }
                    .background(OpenlyTheme.surface)
                    .onAppear { isFocused = true }
                }
            }
            .navigationTitle("اكتب")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func publish() async {
        guard session.requireLogin() else { return }
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPublishing = true
        do {
            _ = try await session.api.createPost(body: text)
            bodyText = ""
            isFocused = false
            onPublished()
        } catch { session.alertMessage = error.localizedDescription }
        isPublishing = false
    }
}

struct PostDetailView: View {
    @EnvironmentObject private var session: AppSession
    let postID: String
    @State private var detail: PostDetailResponse?
    @State private var commentText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                List {
                    Section {
                        PostCard(post: detail.post)
                            .listRowInsets(EdgeInsets())
                    }
                    Section("التعليقات") {
                        if detail.comments.isEmpty {
                            Text("لا توجد تعليقات بعد.")
                                .foregroundColor(OpenlyTheme.muted)
                        } else {
                            ForEach(detail.comments) { comment in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        IdentityBadge(code: comment.authorCode ?? "OPENLY", color: comment.authorColor)
                                        Spacer()
                                        Text(OpenlyDate.relative(comment.createdAt))
                                            .font(.caption)
                                            .foregroundColor(OpenlyTheme.subtle)
                                    }
                                    Text(comment.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if let errorMessage {
                EmptyState(icon: "exclamationmark.triangle", title: "تعذر فتح المنشور", message: errorMessage)
            } else {
                ProgressView("جارِ التحميل")
            }
        }
        .navigationTitle("المحادثة")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if detail != nil {
                HStack(spacing: 10) {
                    TextField("اكتب تعليقًا", text: $commentText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button { Task { await sendComment() } } label: {
                        if isSending { ProgressView() }
                        else { Image(systemName: "paperplane.fill") }
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(10)
                .background(.ultraThinMaterial)
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        do { detail = try await session.api.post(id: postID) }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func sendComment() async {
        guard session.requireLogin() else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        do {
            try await session.api.addComment(postID: postID, body: text)
            commentText = ""
            await load()
        } catch { session.alertMessage = error.localizedDescription }
        isSending = false
    }
}

struct ReportView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let postID: String
    @State private var reason = "spam"
    @State private var description = ""
    @State private var isSending = false

    private let reasons = [
        ("spam", "محتوى مزعج أو مكرر"),
        ("harassment", "مضايقة"),
        ("hate", "خطاب كراهية"),
        ("threat", "تهديد"),
        ("sexual", "محتوى جنسي"),
        ("illegal", "محتوى غير قانوني"),
        ("other", "سبب آخر")
    ]

    var body: some View {
        NavigationView {
            Form {
                Picker("السبب", selection: $reason) {
                    ForEach(reasons, id: \.0) { Text($0.1).tag($0.0) }
                }
                Section("تفاصيل إضافية") {
                    TextEditor(text: $description).frame(minHeight: 110)
                }
            }
            .navigationTitle("إبلاغ عن منشور")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إرسال") { Task { await submit() } }.disabled(isSending)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard session.requireLogin() else { dismiss(); return }
        isSending = true
        do {
            try await session.api.report(postID: postID, reason: reason, description: description)
            dismiss()
        } catch { session.alertMessage = error.localizedDescription }
        isSending = false
    }
}
