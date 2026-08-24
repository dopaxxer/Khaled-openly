import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var posts: [Post] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AppHeader()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        HomeComposerCard {
                            Task { await load(reset: true) }
                        }

                        ScreenHeader("المساحة العامة", subtitle: "الأحدث أولًا. بلا خوارزمية ترتيب.")

                        if posts.isEmpty && isLoading {
                            ForEach(0..<3, id: \.self) { _ in
                                FeedSkeletonRow()
                            }
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
                                        .padding(.horizontal, 28)
                                }
                            }
                        } else {
                            ForEach(posts) { post in
                                PostCard(post: post)
                                    .onAppear {
                                        if post.id == posts.last?.id, nextCursor != nil {
                                            Task { await load(reset: false) }
                                        }
                                    }
                            }

                            if isLoading {
                                ProgressView()
                                    .tint(OpenlyTheme.accent)
                                    .padding(.vertical, 24)
                            } else if nextCursor == nil {
                                Text("هذه كل المنشورات المتاحة.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(OpenlyTheme.subtle)
                                    .padding(.vertical, 28)
                            }
                        }
                    }
                }
                .refreshable { await load(reset: true) }
                .background(OpenlyTheme.background)
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                await load(reset: true)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled, scenePhase == .active else { continue }
                    await load(reset: true)
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await load(reset: true) }
            }
            .onChange(of: session.feedRevision) { _ in
                Task { await load(reset: true) }
            }
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

private struct HomeComposerCard: View {
    @EnvironmentObject private var session: AppSession
    @State private var bodyText = ""
    @State private var isPublishing = false
    @FocusState private var isFocused: Bool
    let onPublished: () -> Void

    var body: some View {
        Group {
            if session.user == nil {
                NavigationLink(destination: LoginView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(OpenlyTheme.accent)
                        Text("سجّل الدخول واكتب شيئًا للجميع…")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OpenlyTheme.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                    .background(OpenlyTheme.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    TextField("ماذا تريد أن تقول؟", text: $bodyText, axis: .vertical)
                        .focused($isFocused)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(OpenlyTheme.ink)
                        .lineLimit(2...5)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(OpenlyTheme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                        )
                        .onChange(of: bodyText) { value in
                            if value.count > postCharacterLimit {
                                bodyText = String(value.prefix(postCharacterLimit))
                            }
                        }

                    HStack(spacing: 12) {
                        Text("\(bodyText.count) / \(postCharacterLimit)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)

                        Spacer()

                        Button {
                            Task { await publish() }
                        } label: {
                            HStack(spacing: 8) {
                                if isPublishing {
                                    ProgressView().tint(OpenlyTheme.accentForeground)
                                } else {
                                    Image(systemName: "paperplane")
                                    Text("نشر")
                                }
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(OpenlyTheme.accentForeground)
                            .padding(.horizontal, 20)
                            .frame(height: 42)
                            .background(OpenlyTheme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                        .opacity(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
                    }
                }
                .padding(14)
                .background(OpenlyTheme.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
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
            session.markFeedChanged()
            onPublished()
        } catch {
            session.alertMessage = error.localizedDescription
        }
        isPublishing = false
    }
}

private struct FeedSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpenlyTheme.surfaceSoft)
                    .frame(width: 94, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpenlyTheme.surfaceSoft)
                    .frame(width: 120, height: 12)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(OpenlyTheme.surfaceSoft)
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 4)
                .fill(OpenlyTheme.surfaceSoft)
                .frame(width: 210, height: 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(OpenlyTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }
}

struct OpenlySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(OpenlyTheme.muted)
            .padding(.horizontal, 20)
            .frame(height: 46)
            .background(Color.clear)
            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1.2))
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
        let code = post.authorCode ?? "OPEN"

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                NavigationLink(destination: UserProfileView(code: code)) {
                    IdentityBadge(code: code, color: post.authorColor)
                }
                .buttonStyle(.plain)
                .disabled(post.authorCode == nil)

                Spacer(minLength: 12)

                Text(OpenlyDate.relative(post.createdAt))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
            }

            NavigationLink(destination: PostDetailView(postID: post.id)) {
                Text(post.body)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(OpenlyTheme.ink)
                    .lineSpacing(7)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                NavigationLink(destination: PostDetailView(postID: post.id)) {
                    actionLabel(
                        icon: "bubble.left",
                        text: (post.commentCount ?? 0) > 0 ? "\(post.commentCount ?? 0) تعليق" : "تعليق",
                        active: false
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button { Task { await toggleLike() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasLiked == true ? "heart.fill" : "heart",
                        text: (engagement?.likeCount ?? 0) > 0 ? "\(engagement?.likeCount ?? 0) إعجاب" : "إعجاب",
                        active: engagement?.viewerHasLiked == true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChanging)
                .frame(maxWidth: .infinity)

                Button { Task { await toggleBookmark() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasBookmarked == true ? "bookmark.fill" : "bookmark",
                        text: engagement?.viewerHasBookmarked == true ? "محفوظ" : "حفظ",
                        active: engagement?.viewerHasBookmarked == true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChanging)
                .frame(maxWidth: .infinity)

                Button { showReport = true } label: {
                    actionLabel(icon: "flag", text: "إبلاغ", active: false)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 25)
        .background(OpenlyTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
        .task { await loadEngagement() }
        .sheet(isPresented: $showReport) { ReportView(postID: post.id) }
    }

    private func actionLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
            Text(text)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(active ? OpenlyTheme.accent : OpenlyTheme.muted)
        .contentShape(Rectangle())
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

/// Matches the server-side posts constraint.
let postCharacterLimit = 3000
let commentCharacterLimit = 2000
let reportDescriptionLimit = 1000

struct ComposerView: View {
    @EnvironmentObject private var session: AppSession
    @State private var bodyText = ""
    @State private var isPublishing = false
    @FocusState private var isFocused: Bool
    let onPublished: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AppHeader()

                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لكتابة منشور جديد.")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ScreenHeader("منشور جديد", subtitle: "سيظهر كلامك للجميع بهويتك الملوّنة. لا توجد مسودات خاصة هنا.")

                            VStack(spacing: 0) {
                                HStack(spacing: 28) {
                                    Image(systemName: "list.bullet")
                                    Text("I").italic()
                                    Text("B").bold()
                                }
                                .font(.system(size: 20))
                                .foregroundColor(OpenlyTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22)
                                .frame(height: 58)

                                Rectangle().fill(OpenlyTheme.line).frame(height: 1)

                                ZStack(alignment: .topLeading) {
                                    if bodyText.isEmpty {
                                        Text("ماذا تريد أن تقول؟")
                                            .font(.system(size: 21, weight: .medium))
                                            .foregroundColor(OpenlyTheme.subtle)
                                            .padding(.horizontal, 17)
                                            .padding(.vertical, 18)
                                            .allowsHitTesting(false)
                                    }

                                    TextEditor(text: $bodyText)
                                        .focused($isFocused)
                                        .font(.system(size: 19, weight: .regular))
                                        .foregroundColor(OpenlyTheme.ink)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.clear)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(minHeight: 230)
                                        .onChange(of: bodyText) { value in
                                            if value.count > postCharacterLimit {
                                                bodyText = String(value.prefix(postCharacterLimit))
                                            }
                                        }
                                }

                                Rectangle().fill(OpenlyTheme.line).frame(height: 1)

                                HStack {
                                    Text("\(bodyText.count) / \(postCharacterLimit)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(OpenlyTheme.subtle)
                                        .environment(\.layoutDirection, .leftToRight)

                                    Spacer()

                                    Button {
                                        Task { await publish() }
                                    } label: {
                                        HStack(spacing: 10) {
                                            if isPublishing {
                                                ProgressView().tint(OpenlyTheme.accentForeground)
                                            } else {
                                                Image(systemName: "paperplane")
                                                Text("نشر")
                                            }
                                        }
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(OpenlyTheme.accentForeground)
                                        .padding(.horizontal, 25)
                                        .frame(height: 48)
                                        .background(OpenlyTheme.accentSoft)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                                    .opacity(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.65 : 1)
                                }
                                .padding(.horizontal, 22)
                                .frame(height: 76)
                            }
                            .background(OpenlyTheme.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(OpenlyTheme.lineStrong, lineWidth: 1.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.horizontal, 18)
                            .padding(.bottom, 30)
                        }
                    }
                    .background(OpenlyTheme.background)
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
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
            session.markFeedChanged()
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        PostCard(post: detail.post)

                        HStack {
                            Text("التعليقات")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(OpenlyTheme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }

                        if detail.comments.isEmpty {
                            Text("لا توجد تعليقات بعد.")
                                .font(.system(size: 15))
                                .foregroundColor(OpenlyTheme.muted)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(detail.comments) { comment in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        IdentityBadge(
                                            code: comment.authorCode ?? "OPEN",
                                            color: comment.authorColor
                                        )
                                        Spacer()
                                        Text(OpenlyDate.relative(comment.createdAt))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(OpenlyTheme.subtle)
                                    }
                                    Text(comment.body)
                                        .font(.system(size: 17))
                                        .foregroundColor(OpenlyTheme.ink)
                                        .lineSpacing(5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 20)
                                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
                            }
                        }
                    }
                }
                .background(OpenlyTheme.background)
            } else if let errorMessage {
                EmptyState(icon: "exclamationmark.triangle", title: "تعذر فتح المنشور", message: errorMessage)
            } else {
                ProgressView("جارِ التحميل")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("المحادثة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if detail != nil {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        OpenlyFieldContainer {
                            TextField("اكتب تعليقًا", text: $commentText, axis: .vertical)
                                .foregroundColor(OpenlyTheme.ink)
                                .lineLimit(1...4)
                                .onChange(of: commentText) { value in
                                    if value.count > commentCharacterLimit {
                                        commentText = String(value.prefix(commentCharacterLimit))
                                    }
                                }
                        }
                        Text("\(commentText.count) / \(commentCharacterLimit)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)
                    }

                    Button { Task { await sendComment() } } label: {
                        if isSending {
                            ProgressView().tint(OpenlyTheme.accentForeground)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 17))
                        }
                    }
                    .foregroundColor(OpenlyTheme.accentForeground)
                    .frame(width: 50, height: 50)
                    .background(OpenlyTheme.accent)
                    .clipShape(Circle())
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(OpenlyTheme.background)
                .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
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
                    TextEditor(text: $description)
                        .frame(minHeight: 110)
                        .onChange(of: description) { value in
                            if value.count > reportDescriptionLimit {
                                description = String(value.prefix(reportDescriptionLimit))
                            }
                        }
                    Text("\(description.count) / \(reportDescriptionLimit)")
                        .font(.caption)
                        .foregroundColor(OpenlyTheme.subtle)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .scrollContentBackground(.hidden)
            .background(OpenlyTheme.background)
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
