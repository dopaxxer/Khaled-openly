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
                OpenlyMobileHeader {
                    HStack(spacing: 8) {
                        if session.user != nil {
                            NavigationLink(destination: NotificationsView()) {
                                Image(systemName: "bell")
                                    .font(.system(size: 19, weight: .regular))
                                    .foregroundColor(OpenlyTheme.muted)
                                    .frame(width: 38, height: 38)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if let user = session.user {
                            NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                                IdentityBadge(code: user.publicCode, color: user.identityColor)
                                    .padding(.horizontal, 11)
                                    .frame(height: 36)
                                    .background(OpenlyTheme.surface.opacity(0.72))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: LoginView()) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(OpenlyTheme.muted)
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                feedBody
            }
            .background(OpenlyTheme.surface)
            .toolbar(.hidden, for: .navigationBar)
            .task { if posts.isEmpty { await load(reset: true) } }
        }
    }

    @ViewBuilder
    private var feedBody: some View {
        if posts.isEmpty && isLoading {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in FeedSkeletonRow() }
                }
            }
            .background(OpenlyTheme.surface)
        } else if posts.isEmpty {
            VStack(spacing: 4) {
                Spacer(minLength: 20)
                EmptyState(
                    icon: errorMessage == nil ? "text.bubble" : "exclamationmark.triangle",
                    title: errorMessage == nil ? "لا توجد منشورات بعد" : "تعذر تحميل المنشورات",
                    message: errorMessage ?? "كن أول من يكتب."
                )
                if errorMessage != nil {
                    Button("المحاولة مجددًا") { Task { await load(reset: true) } }
                        .buttonStyle(OpenlySecondaryButtonStyle())
                }
                Spacer()
            }
            .background(OpenlyTheme.surface)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        PostCard(post: post) { Task { await load(reset: true) } }
                            .onAppear {
                                if post.id == posts.last?.id, nextCursor != nil {
                                    Task { await load(reset: false) }
                                }
                            }
                    }
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else if nextCursor == nil {
                        Text("هذه كل المنشورات المتاحة.")
                            .font(.system(size: 11))
                            .foregroundColor(OpenlyTheme.subtle)
                            .padding(.vertical, 26)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(OpenlyTheme.surface)
            .refreshable { await load(reset: true) }
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
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Capsule().fill(OpenlyTheme.surfaceSoft).frame(width: 105, height: 12)
                Spacer()
                Capsule().fill(OpenlyTheme.surfaceSoft).frame(width: 72, height: 10)
            }
            RoundedRectangle(cornerRadius: 4).fill(OpenlyTheme.surfaceSoft).frame(height: 16)
            RoundedRectangle(cornerRadius: 4).fill(OpenlyTheme.surfaceSoft).frame(width: 250, height: 16)
            Capsule().fill(OpenlyTheme.surfaceSoft).frame(width: 210, height: 11)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenlyTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
    }
}

struct PostCard: View {
    @EnvironmentObject private var session: AppSession
    let post: Post
    var onChanged: (() -> Void)? = nil
    @State private var engagement: Engagement?
    @State private var isChanging = false
    @State private var showReport = false
    @State private var editing = false
    @State private var editText = ""
    @State private var gone = false

    private var isOwner: Bool {
        session.user?.publicCode == post.authorCode
    }

    var body: some View {
        if !gone {
            VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, 12)

                if editing {
                    OpenlyPanel {
                        VStack(spacing: 0) {
                            TextEditor(text: $editText)
                                .font(.system(size: 17))
                                .foregroundColor(OpenlyTheme.foreground)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .frame(minHeight: 120)
                            Rectangle().fill(OpenlyTheme.line).frame(height: 0.5)
                            HStack {
                                Button("إلغاء") { editing = false; editText = post.body }
                                    .buttonStyle(OpenlySecondaryButtonStyle())
                                Spacer()
                                Button(isChanging ? "جارِ الحفظ…" : "حفظ") {
                                    Task { await saveEdit() }
                                }
                                .buttonStyle(OpenlyPrimaryButtonStyle())
                                .disabled(isChanging || editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(12)
                        }
                    }
                } else {
                    NavigationLink(destination: PostDetailView(postID: post.id)) {
                        Text(post.body)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(OpenlyTheme.foreground)
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }

                postActions
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(OpenlyTheme.surface)
            .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
            .task { await loadEngagement() }
            .sheet(isPresented: $showReport) { ReportView(postID: post.id) }
        }
    }

    private var postActions: some View {
        HStack(spacing: 0) {
            NavigationLink(destination: PostDetailView(postID: post.id)) {
                actionLabel(
                    icon: "bubble.left",
                    text: (post.commentCount ?? 0) > 0 ? "\(post.commentCount ?? 0) تعليق" : "تعليق",
                    color: OpenlyTheme.muted
                )
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)

            Button { Task { await toggleLike() } } label: {
                actionLabel(
                    icon: engagement?.viewerHasLiked == true ? "heart.fill" : "heart",
                    text: (engagement?.likeCount ?? 0) > 0 ? "\(engagement?.likeCount ?? 0)" : "إعجاب",
                    color: engagement?.viewerHasLiked == true ? Color(red: 212/255, green: 72/255, blue: 60/255) : OpenlyTheme.muted
                )
            }
            .buttonStyle(.plain)
            .disabled(isChanging)
            Spacer(minLength: 8)

            Button { Task { await toggleBookmark() } } label: {
                actionLabel(
                    icon: engagement?.viewerHasBookmarked == true ? "bookmark.fill" : "bookmark",
                    text: engagement?.viewerHasBookmarked == true ? "محفوظ" : "حفظ",
                    color: engagement?.viewerHasBookmarked == true ? OpenlyTheme.accent : OpenlyTheme.muted
                )
            }
            .buttonStyle(.plain)
            .disabled(isChanging)
            Spacer(minLength: 8)

            Menu {
                if isOwner {
                    Button {
                        editText = post.body
                        editing = true
                    } label: { Label("تعديل", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await removePost() } } label: {
                        Label("حذف", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) { showReport = true } label: {
                        Label("إبلاغ", systemImage: "flag")
                    }
                }
            } label: {
                actionLabel(icon: "ellipsis", text: isOwner ? "إدارة" : "إبلاغ", color: OpenlyTheme.muted)
            }
        }
    }

    private func actionLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .regular))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
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
        let previous = engagement
        if var current = engagement {
            current.viewerHasLiked = next
            current.likeCount = max(0, current.likeCount + (next ? 1 : -1))
            engagement = current
        }
        isChanging = true
        do {
            try await session.api.setLike(postID: post.id, enabled: next)
            await loadEngagement()
        } catch {
            engagement = previous
            session.alertMessage = error.localizedDescription
        }
        isChanging = false
    }

    @MainActor
    private func toggleBookmark() async {
        guard session.requireLogin() else { return }
        let next = !(engagement?.viewerHasBookmarked ?? false)
        let previous = engagement
        if var current = engagement {
            current.viewerHasBookmarked = next
            engagement = current
        }
        isChanging = true
        do {
            try await session.api.setBookmark(postID: post.id, enabled: next)
            await loadEngagement()
        } catch {
            engagement = previous
            session.alertMessage = error.localizedDescription
        }
        isChanging = false
    }

    @MainActor
    private func saveEdit() async {
        let value = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isChanging = true
        do {
            try await session.api.updatePost(postID: post.id, body: value)
            editing = false
            onChanged?()
        } catch { session.alertMessage = error.localizedDescription }
        isChanging = false
    }

    @MainActor
    private func removePost() async {
        guard session.requireLogin() else { return }
        isChanging = true
        do {
            try await session.api.deletePost(postID: post.id)
            gone = true
            onChanged?()
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
        NavigationStack {
            ZStack {
                CosmicBackground()
                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لكتابة منشور جديد.")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ScreenHeader("منشور جديد", subtitle: "سيظهر كلامك للجميع بهويتك الملوّنة. لا توجد مسودات خاصة هنا.")
                            OpenlyPanel {
                                VStack(spacing: 0) {
                                    HStack(spacing: 3) {
                                        formattingButton("bold", token: "**")
                                        formattingButton("italic", token: "*")
                                        formattingButton("list.bullet", token: "\n• ")
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 48)
                                    Rectangle().fill(OpenlyTheme.line).frame(height: 0.5)

                                    TextEditor(text: $bodyText)
                                        .focused($isFocused)
                                        .font(.system(size: 18))
                                        .foregroundColor(OpenlyTheme.foreground)
                                        .scrollContentBackground(.hidden)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .frame(minHeight: 150, maxHeight: 390)
                                        .overlay(alignment: .topLeading) {
                                            if bodyText.isEmpty {
                                                Text("ماذا تريد أن تقول؟")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(OpenlyTheme.subtle)
                                                    .padding(.horizontal, 23)
                                                    .padding(.vertical, 20)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                        .onChange(of: bodyText) { value in
                                            if value.count > 3000 { bodyText = String(value.prefix(3000)) }
                                        }

                                    Rectangle().fill(OpenlyTheme.line).frame(height: 0.5)
                                    HStack {
                                        Text("\(bodyText.count) / 3000")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(bodyText.count > 2800 ? OpenlyTheme.danger : OpenlyTheme.subtle)
                                            .environment(\.layoutDirection, .leftToRight)
                                        Spacer()
                                        Button {
                                            Task { await publish() }
                                        } label: {
                                            HStack(spacing: 7) {
                                                if isPublishing { ProgressView().tint(.white).controlSize(.small) }
                                                else { Image(systemName: "paperplane") }
                                                Text(isPublishing ? "جارِ النشر…" : "نشر")
                                            }
                                        }
                                        .buttonStyle(OpenlyPrimaryButtonStyle())
                                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { if session.user != nil { isFocused = true } }
        }
    }

    private func formattingButton(_ icon: String, token: String) -> some View {
        Button {
            bodyText += token
            isFocused = true
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .frame(width: 34, height: 34)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
        ZStack {
            OpenlyTheme.surface.ignoresSafeArea()
            if let detail {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        PostCard(post: detail.post) { Task { await load() } }
                        commentComposer
                        HStack {
                            Text("التعليقات")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(OpenlyTheme.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                        .padding(.bottom, 10)

                        if detail.comments.isEmpty {
                            EmptyState(icon: "", title: "لا توجد تعليقات بعد", message: "ابدأ المحادثة بتعليق جديد.")
                        } else {
                            ForEach(detail.comments) { comment in
                                CommentRow(comment: comment)
                            }
                        }
                    }
                }
            } else if let errorMessage {
                EmptyState(icon: "exclamationmark.triangle", title: "تعذر فتح المنشور", message: errorMessage)
            } else {
                ProgressView("جارِ التحميل")
                    .foregroundColor(OpenlyTheme.muted)
            }
        }
        .navigationTitle("المحادثة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .task { await load() }
    }

    private var commentComposer: some View {
        VStack(spacing: 12) {
            TextEditor(text: $commentText)
                .font(.system(size: 16))
                .foregroundColor(OpenlyTheme.foreground)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 105)
                .background(OpenlyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: OpenlyTheme.radiusLarge))
                .overlay(RoundedRectangle(cornerRadius: OpenlyTheme.radiusLarge).stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                .onChange(of: commentText) { value in
                    if value.count > 2000 { commentText = String(value.prefix(2000)) }
                }
            HStack {
                Text("\(commentText.count) / 2000")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(OpenlyTheme.subtle)
                Spacer()
                Button(isSending ? "جارِ الإرسال…" : "تعليق") { Task { await sendComment() } }
                    .buttonStyle(OpenlyPrimaryButtonStyle())
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
    }

    @MainActor
    private func load() async {
        do {
            detail = try await session.api.post(id: postID)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
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

private struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IdentityBadge(code: comment.authorCode ?? "OPENLY", color: comment.authorColor)
                Spacer()
                Text(OpenlyDate.relative(comment.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(OpenlyTheme.subtle)
            }
            Text(comment.body)
                .font(.system(size: 16))
                .foregroundColor(OpenlyTheme.foreground)
                .lineSpacing(7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 22)
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
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
            ZStack {
                CosmicBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader("إبلاغ عن منشور", subtitle: "ساعدنا في إبقاء المساحة العامة واضحة وآمنة.")
                        VStack(alignment: .leading, spacing: 10) {
                            Text("السبب").font(.system(size: 14, weight: .semibold)).foregroundColor(OpenlyTheme.foreground)
                            Picker("السبب", selection: $reason) {
                                ForEach(reasons, id: \.0) { Text($0.1).tag($0.0) }
                            }
                            .pickerStyle(.menu)
                            .tint(OpenlyTheme.accent)
                        }
                        .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("تفاصيل إضافية").font(.system(size: 14, weight: .semibold)).foregroundColor(OpenlyTheme.foreground)
                            TextEditor(text: $description)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .frame(minHeight: 120)
                                .background(OpenlyTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                        }
                        .padding(.horizontal, 16)

                        Button(isSending ? "جارِ الإرسال…" : "إرسال البلاغ") { Task { await submit() } }
                            .buttonStyle(OpenlyPrimaryButtonStyle())
                            .disabled(isSending)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                }
            }
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
        } catch { session.alertMessage = error.localizedDescription }
        isSending = false
    }
}
