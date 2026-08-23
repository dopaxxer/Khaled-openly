import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var session: AppSession
    @State private var posts: [Post] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OpenlyTopBar {
                    Group {
                        if session.user != nil {
                            NavigationLink(destination: NotificationsView()) {
                                OpenlyIconButton(systemName: "bell", badge: session.unreadCount)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: LoginView()) {
                                OpenlyIconButton(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 74, alignment: .leading)
                } trailing: {
                    Group {
                        if let user = session.user {
                            NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(Color(hex: user.identityColor) ?? OpenlyTheme.accent)
                                        .frame(width: 8, height: 8)
                                    Text(user.publicCode)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .tracking(0.6)
                                        .foregroundStyle(OpenlyTheme.foreground)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 42, height: 42)
                        }
                    }
                    .frame(width: 74, alignment: .trailing)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ScreenHeader("المساحة العامة", subtitle: "الأحدث أولًا. بلا خوارزمية ترتيب.")

                        if posts.isEmpty && isLoading {
                            ForEach(0..<3, id: \.self) { _ in FeedSkeletonRow() }
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
                            .padding(.bottom, 40)
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
                                    .controlSize(.small)
                                    .padding(.vertical, 28)
                            } else if nextCursor == nil {
                                Text("هذه كل المنشورات المتاحة.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(OpenlyTheme.subtle)
                                    .padding(.vertical, 30)
                            }
                        }
                    }
                }
                .refreshable { await load(reset: true) }
                .background(OpenlyTheme.surface)
            }
            .background(OpenlyTheme.surface)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if posts.isEmpty { await load(reset: true) }
                await session.refreshUnread()
            }
        }
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
            if reset {
                posts = response.items
            } else {
                posts += response.items.filter { item in !posts.contains(where: { $0.id == item.id }) }
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
        VStack(alignment: .leading, spacing: 13) {
            RoundedRectangle(cornerRadius: 8).fill(OpenlyTheme.surfaceSoft).frame(width: 116, height: 12)
            RoundedRectangle(cornerRadius: 8).fill(OpenlyTheme.surfaceSoft).frame(height: 13)
            RoundedRectangle(cornerRadius: 8).fill(OpenlyTheme.surfaceSoft).frame(width: 235, height: 13)
            RoundedRectangle(cornerRadius: 8).fill(OpenlyTheme.surfaceSoft).frame(width: 190, height: 10)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
    }
}

struct PostCard: View {
    @EnvironmentObject private var session: AppSession
    let post: Post
    @State private var engagement: Engagement?
    @State private var isChanging = false
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let code = post.authorCode {
                    NavigationLink(destination: UserProfileView(code: code)) {
                        IdentityBadge(code: code, color: post.authorColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    IdentityBadge(code: "OPENLY", color: post.authorColor)
                }
                Spacer(minLength: 12)
                Text(OpenlyDate.relative(post.createdAt))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(OpenlyTheme.subtle)
            }
            .padding(.bottom, 13)

            NavigationLink(destination: PostDetailView(postID: post.id)) {
                Text(post.body)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(OpenlyTheme.foreground)
                    .lineSpacing(7)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)

            HStack(spacing: 24) {
                NavigationLink(destination: PostDetailView(postID: post.id)) {
                    actionLabel(
                        icon: "bubble.left",
                        text: (post.commentCount ?? 0) > 0 ? "\(post.commentCount ?? 0) تعليق" : "تعليق",
                        color: OpenlyTheme.muted
                    )
                }
                .buttonStyle(.plain)

                Button { Task { await toggleLike() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasLiked == true ? "heart.fill" : "heart",
                        text: (engagement?.likeCount ?? 0) > 0 ? "\(engagement?.likeCount ?? 0)" : "إعجاب",
                        color: engagement?.viewerHasLiked == true ? OpenlyTheme.like : OpenlyTheme.muted
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChanging)

                Button { Task { await toggleBookmark() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasBookmarked == true ? "bookmark.fill" : "bookmark",
                        text: engagement?.viewerHasBookmarked == true ? "محفوظ" : "حفظ",
                        color: engagement?.viewerHasBookmarked == true ? OpenlyTheme.accent : OpenlyTheme.muted
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChanging)

                Spacer(minLength: 0)

                Button { showReport = true } label: {
                    actionLabel(icon: "flag", text: "إبلاغ", color: OpenlyTheme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .background(OpenlyTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
        .task { await loadEngagement() }
        .sheet(isPresented: $showReport) { ReportView(postID: post.id) }
    }

    private func actionLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15.5, weight: .regular))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .frame(minHeight: 32)
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
        let old = engagement
        let optimisticCount = max(0, (engagement?.likeCount ?? 0) + (next ? 1 : -1))
        engagement = Engagement(postId: post.id, likeCount: optimisticCount, viewerHasLiked: next, viewerHasBookmarked: engagement?.viewerHasBookmarked ?? false)
        isChanging = true
        do {
            try await session.api.setLike(postID: post.id, enabled: next)
            await loadEngagement()
        } catch {
            engagement = old
            session.alertMessage = error.localizedDescription
        }
        isChanging = false
    }

    @MainActor
    private func toggleBookmark() async {
        guard session.requireLogin() else { return }
        let next = !(engagement?.viewerHasBookmarked ?? false)
        let old = engagement
        engagement = Engagement(postId: post.id, likeCount: engagement?.likeCount ?? 0, viewerHasLiked: engagement?.viewerHasLiked ?? false, viewerHasBookmarked: next)
        isChanging = true
        do {
            try await session.api.setBookmark(postID: post.id, enabled: next)
            await loadEngagement()
        } catch {
            engagement = old
            session.alertMessage = error.localizedDescription
        }
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ScreenHeader("منشور جديد", subtitle: "سيظهر كلامك للجميع بهويتك الملوّنة. لا توجد مسودات خاصة هنا.")

                    if session.user == nil {
                        LoginRequiredView(message: "سجّل الدخول لكتابة منشور جديد.")
                            .padding(.horizontal, 18)
                    } else {
                        OpenlyCard {
                            VStack(spacing: 0) {
                                HStack(spacing: 2) {
                                    formatButton("bold", marker: "**")
                                    formatButton("italic", marker: "*")
                                    Button { insertListPrefix() } label: {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(OpenlyTheme.muted)
                                            .frame(width: 34, height: 34)
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }

                                ZStack(alignment: .topLeading) {
                                    if bodyText.isEmpty {
                                        Text("ماذا تريد أن تقول؟")
                                            .font(.system(size: 18))
                                            .foregroundStyle(OpenlyTheme.subtle)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 17)
                                    }
                                    TextEditor(text: $bodyText)
                                        .focused($isFocused)
                                        .scrollContentBackground(.hidden)
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundStyle(OpenlyTheme.foreground)
                                        .lineSpacing(8)
                                        .frame(minHeight: 135, maxHeight: 360)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .onChange(of: bodyText) { value in
                                            if value.count > 3000 { bodyText = String(value.prefix(3000)) }
                                        }
                                }

                                HStack(spacing: 14) {
                                    Text("\(bodyText.count) / 3000")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(bodyText.count > 2800 ? OpenlyTheme.danger : OpenlyTheme.subtle)
                                        .environment(\.layoutDirection, .leftToRight)
                                    Spacer()
                                    Button {
                                        Task { await publish() }
                                    } label: {
                                        HStack(spacing: 7) {
                                            if isPublishing { ProgressView().tint(.white).controlSize(.small) }
                                            else { Image(systemName: "paperplane.fill").font(.system(size: 13)) }
                                            Text(isPublishing ? "جارِ النشر…" : "نشر")
                                        }
                                    }
                                    .buttonStyle(OpenlyPrimaryButtonStyle())
                                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                                    .opacity(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 13)
                                .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(OpenlyTheme.surface)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { isFocused = session.user != nil }
        }
    }

    private func formatButton(_ systemName: String, marker: String) -> some View {
        Button { wrapSelectionFallback(marker: marker) } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OpenlyTheme.muted)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private func wrapSelectionFallback(marker: String) {
        if bodyText.isEmpty { bodyText = marker + marker }
        else { bodyText += "\n\(marker)نص\(marker)" }
    }

    private func insertListPrefix() {
        bodyText += bodyText.isEmpty ? "• " : "\n• "
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
        } catch {
            session.alertMessage = error.localizedDescription
        }
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
    @FocusState private var commentFocused: Bool

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        PostCard(post: detail.post)
                        HStack {
                            Text("التعليقات")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(OpenlyTheme.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 28)
                        .padding(.bottom, 10)

                        if detail.comments.isEmpty {
                            EmptyState(icon: "bubble.left", title: "لا توجد تعليقات بعد", message: "ابدأ المحادثة من الأسفل.")
                        } else {
                            ForEach(rootComments(detail.comments)) { comment in
                                CommentNodeView(comment: comment, allComments: detail.comments, postID: postID, onChanged: { Task { await load() } })
                            }
                        }
                    }
                }
                .background(OpenlyTheme.surface)
            } else if let errorMessage {
                EmptyState(icon: "exclamationmark.triangle", title: "تعذر فتح المنشور", message: errorMessage)
                    .background(OpenlyTheme.surface)
            } else {
                ProgressView("جارِ التحميل")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OpenlyTheme.surface)
            }
        }
        .navigationTitle("المحادثة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if detail != nil {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("اكتب تعليقًا", text: $commentText, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(1...5)
                        .focused($commentFocused)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(OpenlyTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                    Button { Task { await sendComment() } } label: {
                        ZStack {
                            Circle().fill(OpenlyTheme.accent)
                            if isSending { ProgressView().tint(.white).controlSize(.small) }
                            else { Image(systemName: "paperplane.fill").font(.system(size: 14)).foregroundStyle(.white) }
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .opacity(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial)
                .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
            }
        }
        .task { await load() }
    }

    private func rootComments(_ comments: [Comment]) -> [Comment] {
        comments.filter { $0.parentCommentId == nil }
    }

    @MainActor
    private func load() async {
        do {
            detail = try await session.api.post(id: postID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
            commentFocused = false
            await load()
        } catch {
            session.alertMessage = error.localizedDescription
        }
        isSending = false
    }
}

private struct CommentNodeView: View {
    @EnvironmentObject private var session: AppSession
    let comment: Comment
    let allComments: [Comment]
    let postID: String
    let onChanged: () -> Void
    @State private var replying = false
    @State private var replyText = ""
    @State private var sending = false

    private var children: [Comment] { allComments.filter { $0.parentCommentId == comment.id } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IdentityBadge(code: comment.authorCode ?? "OPENLY", color: comment.authorColor)
                    Spacer()
                    Text(OpenlyDate.relative(comment.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(OpenlyTheme.subtle)
                }
                Text(comment.body)
                    .font(.system(size: 16))
                    .foregroundStyle(OpenlyTheme.foreground)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { replying.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrowshape.turn.up.left")
                        Text("رد")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OpenlyTheme.muted)
                }
                .buttonStyle(.plain)

                if replying {
                    VStack(spacing: 10) {
                        TextField("اكتب ردًا", text: $replyText, axis: .vertical)
                            .lineLimit(1...4)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(OpenlyTheme.surfaceSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        HStack {
                            Button("إلغاء") { replying = false; replyText = "" }
                                .buttonStyle(OpenlySecondaryButtonStyle())
                            Button(sending ? "جارِ الإرسال…" : "إرسال") { Task { await sendReply() } }
                                .buttonStyle(OpenlyPrimaryButtonStyle())
                                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                        }
                    }
                    .padding(12)
                    .background(OpenlyTheme.surfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }

            if !children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(children) { child in
                        CommentNodeView(comment: child, allComments: allComments, postID: postID, onChanged: onChanged)
                    }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) { Rectangle().fill(OpenlyTheme.line).frame(width: 2) }
                .padding(.leading, 18)
            }
        }
    }

    @MainActor
    private func sendReply() async {
        guard session.requireLogin() else { return }
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        do {
            try await session.api.addComment(postID: postID, body: text, parentID: comment.id)
            replyText = ""
            replying = false
            onChanged()
        } catch {
            session.alertMessage = error.localizedDescription
        }
        sending = false
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeader("إبلاغ عن منشور", subtitle: "اختر السبب وأضف تفاصيل إذا احتجت.")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("السبب").font(.system(size: 13, weight: .semibold)).foregroundStyle(OpenlyTheme.muted)
                        Picker("السبب", selection: $reason) {
                            ForEach(reasons, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .pickerStyle(.menu)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("تفاصيل إضافية").font(.system(size: 13, weight: .semibold)).foregroundStyle(OpenlyTheme.muted)
                        TextEditor(text: $description)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 130)
                            .padding(10)
                            .background(OpenlyTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                    }
                    Button { Task { await submit() } } label: {
                        Text(isSending ? "جارِ الإرسال…" : "إرسال البلاغ").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OpenlyPrimaryButtonStyle())
                    .disabled(isSending)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }
            .background(OpenlyTheme.background)
            .navigationTitle("إبلاغ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
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
        } catch {
            session.alertMessage = error.localizedDescription
        }
        isSending = false
    }
}
