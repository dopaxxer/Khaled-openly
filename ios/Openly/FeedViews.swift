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
                    ProgressView("جارِ تحميل المنشورات")
                } else if posts.isEmpty {
                    EmptyState(
                        icon: "text.bubble",
                        title: "لا توجد منشورات بعد",
                        message: errorMessage ?? "كن أول من يكتب في المساحة العامة."
                    )
                } else {
                    List {
                        ForEach(posts) { post in
                            PostCard(post: post)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    if post.id == posts.last?.id, nextCursor != nil {
                                        Task { await load(reset: false) }
                                    }
                                }
                        }
                        if isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load(reset: true) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        BrandMark(size: 29)
                        Text("Openly")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .environment(\.layoutDirection, .leftToRight)
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct PostCard: View {
    @EnvironmentObject private var session: AppSession
    let post: Post
    @State private var engagement: Engagement?
    @State private var isChanging = false
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                Menu {
                    Button(role: .destructive) { showReport = true } label: {
                        Label("إبلاغ", systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }

            NavigationLink(destination: PostDetailView(postID: post.id)) {
                Text(post.body)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 24) {
                Button { Task { await toggleLike() } } label: {
                    Label(
                        "\(engagement?.likeCount ?? 0)",
                        systemImage: engagement?.viewerHasLiked == true ? "heart.fill" : "heart"
                    )
                    .foregroundColor(engagement?.viewerHasLiked == true ? .red : .secondary)
                }
                .disabled(isChanging)

                NavigationLink(destination: PostDetailView(postID: post.id)) {
                    Label("\(post.commentCount ?? 0)", systemImage: "bubble.left")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button { Task { await toggleBookmark() } } label: {
                    Image(systemName: engagement?.viewerHasBookmarked == true ? "bookmark.fill" : "bookmark")
                        .foregroundColor(engagement?.viewerHasBookmarked == true ? OpenlyTheme.accent : .secondary)
                }
                .disabled(isChanging)
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .task { await loadEngagement() }
        .sheet(isPresented: $showReport) { ReportView(postID: post.id) }
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
                            .background(OpenlyTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal)
                            .onChange(of: bodyText) { value in
                                if value.count > 3000 { bodyText = String(value.prefix(3000)) }
                            }

                        HStack {
                            Text("\(bodyText.count) / 3000")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                            .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                        }
                        .padding(.horizontal)
                        Spacer()
                    }
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
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(detail.comments) { comment in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        IdentityBadge(code: comment.authorCode ?? "OPENLY", color: comment.authorColor)
                                        Spacer()
                                        Text(OpenlyDate.relative(comment.createdAt))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
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
