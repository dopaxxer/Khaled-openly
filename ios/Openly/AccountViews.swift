import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: AppSession
    @State private var query = ""
    @State private var result: SearchResponse?
    @State private var isLoading = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("كلمات أو كود هوية", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if !query.isEmpty {
                        Button { query = ""; result = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(OpenlyTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding()

                if isLoading {
                    ProgressView("جارِ البحث")
                    Spacer()
                } else if let result {
                    List {
                        if !result.users.isEmpty {
                            Section("الهويات") {
                                ForEach(result.users) { user in
                                    NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                                        IdentityBadge(code: user.publicCode, color: user.identityColor)
                                    }
                                }
                            }
                        }
                        if !result.posts.isEmpty {
                            Section("المنشورات") {
                                ForEach(result.posts) { post in
                                    PostCard(post: post).listRowInsets(EdgeInsets())
                                }
                            }
                        }
                        if result.users.isEmpty && result.posts.isEmpty {
                            EmptyState(icon: "magnifyingglass", title: "لا توجد نتائج", message: "جرّب كلمة أو كودًا مختلفًا.")
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    EmptyState(icon: "text.magnifyingglass", title: "ابحث في Openly", message: "ابحث عن الكلمات العامة أو أكواد الهوية.")
                    Spacer()
                }
            }
            .navigationTitle("بحث")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { result = nil; return }
        focused = false
        isLoading = true
        do { result = try await session.api.search(text) }
        catch { session.alertMessage = error.localizedDescription }
        isLoading = false
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var response: NotificationResponse?
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            Group {
                if session.user == nil {
                    LoginRequiredView(message: "سجّل الدخول لرؤية الإشعارات.")
                } else if isLoading && response == nil {
                    ProgressView("جارِ تحميل الإشعارات")
                } else if let items = response?.items, !items.isEmpty {
                    List(items) { item in
                        NavigationLink(destination: destination(for: item)) {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(Color(hex: item.actorColor) ?? OpenlyTheme.accent)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(notificationText(item))
                                        .fontWeight(item.readAt == nil ? .semibold : .regular)
                                    Text(OpenlyDate.relative(item.createdAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if item.readAt == nil {
                                    Circle().fill(OpenlyTheme.accent).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                } else {
                    EmptyState(icon: "bell.slash", title: "لا توجد إشعارات", message: "ستظهر هنا الإعجابات والردود المرتبطة بك.")
                }
            }
            .navigationTitle("الإشعارات")
            .navigationBarTitleDisplayMode(.inline)
            .task { if session.user != nil { await load() } }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func destination(for item: NotificationItem) -> some View {
        if let id = item.postId { PostDetailView(postID: id) }
        else { EmptyState(icon: "bell", title: "إشعار", message: notificationText(item)) }
    }

    private func notificationText(_ item: NotificationItem) -> String {
        let actor = item.actorCode ?? "أحد المستخدمين"
        switch item.kind {
        case "like": return "أعجب \(actor) بمنشورك"
        case "comment", "reply": return "ردّ \(actor) على منشورك"
        case "follow": return "بدأ \(actor) بمتابعتك"
        default: return "تفاعل \(actor) مع محتواك"
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            let value = try await session.api.notifications()
            response = value
            let unread = value.items.filter { $0.readAt == nil }.map(\.id)
            if !unread.isEmpty { try? await session.api.markNotificationsRead(ids: unread) }
        } catch { session.alertMessage = error.localizedDescription }
        isLoading = false
    }
}

struct AccountView: View {
    @EnvironmentObject private var session: AppSession
    @State private var followersCount = 0

    var body: some View {
        NavigationView {
            Group {
                if let user = session.user {
                    List {
                        Section {
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: user.identityColor) ?? OpenlyTheme.accent)
                                    .frame(width: 62, height: 62)
                                    .overlay(Image(systemName: "text.quote").foregroundColor(.white).font(.title2))
                                Text(user.publicCode)
                                    .font(.system(.title2, design: .monospaced).weight(.bold))
                                    .environment(\.layoutDirection, .leftToRight)
                                Text("انضم في \(OpenlyDate.short(user.createdAt))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let bio = user.bio, !bio.isEmpty { Text(bio).font(.subheadline) }
                                Text("\(followersCount) متابع")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }

                        Section {
                            NavigationLink(destination: UserPostsView(code: user.publicCode)) {
                                Label("كتاباتي", systemImage: "text.bubble")
                            }
                            NavigationLink(destination: BookmarksView()) {
                                Label("المحفوظات", systemImage: "bookmark")
                            }
                            NavigationLink(destination: FollowingView()) {
                                Label("الأكواد التي أتابعها", systemImage: "person.2")
                            }
                            NavigationLink(destination: PrivacyView()) {
                                Label("الخصوصية", systemImage: "hand.raised")
                            }
                        }

                        Section {
                            Button(role: .destructive) { Task { await session.logout() } } label: {
                                Label("تسجيل الخروج", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .task { followersCount = (try? await session.api.followersCount()) ?? 0 }
                } else {
                    LoginView()
                }
            }
            .navigationTitle("حسابي")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

struct LoginRequiredView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            BrandMark(size: 54)
            Text(message).multilineTextAlignment(.center)
            NavigationLink(destination: LoginView()) {
                Text("تسجيل الدخول").frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var showRegister = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BrandMark(size: 62)
                VStack(spacing: 5) {
                    Text("مرحبًا بعودتك").font(.title2.bold())
                    Text("ادخل إلى هويتك وكلماتك.").foregroundColor(.secondary)
                }
                VStack(spacing: 12) {
                    TextField("البريد الإلكتروني", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                    SecureField("كلمة المرور", text: $password)
                        .textContentType(.password)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .textFieldStyle(.roundedBorder)

                Button { Task { await login() } } label: {
                    Group {
                        if isSubmitting { ProgressView().tint(.white) }
                        else { Text("تسجيل الدخول") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)

                Button("ليس لديك حساب؟ أنشئ هويتك") { showRegister = true }
                    .font(.subheadline)
            }
            .padding(24)
        }
        .sheet(isPresented: $showRegister) { RegisterView() }
    }

    @MainActor
    private func login() async {
        isSubmitting = true
        do { try await session.login(email: email, password: password) }
        catch { session.alertMessage = error.localizedDescription }
        isSubmitting = false
    }
}

struct RegisterView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var verificationEmail: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationView {
            Group {
                if let verificationEmail {
                    VerificationView(email: verificationEmail) {
                        Task { await session.refresh(); dismiss() }
                    }
                } else {
                    Form {
                        Section("أنشئ هويتك") {
                            TextField("البريد الإلكتروني", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("كلمة المرور — 8 أحرف على الأقل", text: $password)
                            SecureField("تأكيد كلمة المرور", text: $confirmation)
                        }
                        Section {
                            Button { Task { await register() } } label: {
                                HStack {
                                    Spacer()
                                    if isSubmitting { ProgressView() } else { Text("إنشاء الحساب") }
                                    Spacer()
                                }
                            }
                            .disabled(!formIsValid || isSubmitting)
                        } footer: {
                            Text("سيمنحك Openly كودًا ولونًا ثابتين دون اسم عرض أو صورة شخصية.")
                        }
                    }
                }
            }
            .navigationTitle("حساب جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            }
        }
    }

    private var formIsValid: Bool {
        email.contains("@") && password.count >= 8 && password == confirmation
    }

    @MainActor
    private func register() async {
        isSubmitting = true
        do {
            let response = try await session.api.register(email: email, password: password)
            if response.requiresEmailConfirmation == true {
                verificationEmail = response.email ?? email
            } else {
                await session.refresh()
                dismiss()
            }
        } catch { session.alertMessage = error.localizedDescription }
        isSubmitting = false
    }
}

struct VerificationView: View {
    @EnvironmentObject private var session: AppSession
    let email: String
    let onVerified: () -> Void
    @State private var token = ""
    @State private var isSubmitting = false
    @State private var status: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.badge").font(.system(size: 48)).foregroundColor(OpenlyTheme.accent)
            Text("تحقق من بريدك").font(.title2.bold())
            Text("أرسلنا كودًا من 6 أرقام إلى\n\(email)")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            TextField("000000", text: $token)
                .keyboardType(.numberPad)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: token) { value in
                    token = String(value.filter(\.isNumber).prefix(6))
                }
            Button("تأكيد الكود") { Task { await verify() } }
                .buttonStyle(.borderedProminent)
                .disabled(token.count != 6 || isSubmitting)
            Button("إعادة إرسال الكود") { Task { await resend() } }.font(.subheadline)
            if let status { Text(status).font(.footnote).foregroundColor(.secondary) }
        }
        .padding(24)
    }

    @MainActor
    private func verify() async {
        isSubmitting = true
        do {
            try await session.api.verify(email: email, token: token)
            onVerified()
        } catch { session.alertMessage = error.localizedDescription }
        isSubmitting = false
    }

    @MainActor
    private func resend() async {
        do {
            try await session.api.resendCode(email: email)
            status = "تم إرسال كود جديد."
        } catch { session.alertMessage = error.localizedDescription }
    }
}

struct UserProfileView: View {
    @EnvironmentObject private var session: AppSession
    let code: String
    @State private var user: UserSummary?
    @State private var posts: [Post] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if let user {
                Section {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: user.identityColor) ?? OpenlyTheme.accent)
                            .frame(width: 58, height: 58)
                        Text(user.publicCode)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .environment(\.layoutDirection, .leftToRight)
                        if let bio = user.bio, !bio.isEmpty { Text(bio).multilineTextAlignment(.center) }
                        Text("انضم في \(OpenlyDate.short(user.createdAt))")
                            .font(.caption).foregroundColor(.secondary)
                        if user.isSelf != true {
                            HStack {
                                Button(user.viewerIsFollowing == true ? "إلغاء المتابعة" : "متابعة") {
                                    Task { await setRelation("follow", enabled: user.viewerIsFollowing != true) }
                                }
                                .buttonStyle(.borderedProminent)
                                Menu {
                                    Button(user.viewerHasMuted == true ? "إلغاء الكتم" : "كتم") {
                                        Task { await setRelation("mute", enabled: user.viewerHasMuted != true) }
                                    }
                                    Button(user.viewerHasBlocked == true ? "إلغاء الحظر" : "حظر", role: .destructive) {
                                        Task { await setRelation("block", enabled: user.viewerHasBlocked != true) }
                                    }
                                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                Section("الكتابات") {
                    if posts.isEmpty { Text("لا توجد منشورات.").foregroundColor(.secondary) }
                    ForEach(posts) { post in PostCard(post: post).listRowInsets(EdgeInsets()) }
                }
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
        .navigationTitle(code)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            async let profile = session.api.user(code: code)
            async let feed = session.api.feed(author: code)
            user = try await profile
            let feedResult = try await feed
            posts = feedResult.items
        } catch { session.alertMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func setRelation(_ kind: String, enabled: Bool) async {
        guard session.requireLogin() else { return }
        do {
            try await session.api.setRelation(code: code, kind: kind, enabled: enabled)
            user = try await session.api.user(code: code)
        } catch { session.alertMessage = error.localizedDescription }
    }
}

struct UserPostsView: View {
    @EnvironmentObject private var session: AppSession
    let code: String
    @State private var posts: [Post] = []

    var body: some View {
        List(posts) { PostCard(post: $0).listRowInsets(EdgeInsets()) }
            .listStyle(.plain)
            .navigationTitle("كتاباتي")
            .task { posts = (try? await session.api.feed(author: code))?.items ?? [] }
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var session: AppSession
    @State private var posts: [Post] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if posts.isEmpty { EmptyState(icon: "bookmark", title: "لا توجد محفوظات", message: "المنشورات التي تحفظها ستظهر هنا.") }
            else { List(posts) { PostCard(post: $0).listRowInsets(EdgeInsets()) }.listStyle(.plain) }
        }
        .navigationTitle("المحفوظات")
        .task {
            posts = (try? await session.api.bookmarks()) ?? []
            isLoading = false
        }
    }
}

struct FollowingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var users: [UserSummary] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if users.isEmpty { EmptyState(icon: "person.2", title: "لا تتابع أي كود", message: "ستظهر هنا الهويات التي تتابعها.") }
            else {
                List(users) { user in
                    NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                        IdentityBadge(code: user.publicCode, color: user.identityColor)
                    }
                }
            }
        }
        .navigationTitle("المتابَعون")
        .task {
            users = (try? await session.api.following()) ?? []
            isLoading = false
        }
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var session: AppSession
    @State private var relations: [PrivacyRelation] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else if relations.isEmpty { EmptyState(icon: "hand.raised", title: "لا توجد علاقات خصوصية", message: "الحسابات المكتومة والمحظورة ستظهر هنا.") }
            else {
                List(relations) { relation in
                    HStack {
                        IdentityBadge(code: relation.publicCode, color: relation.identityColor)
                        Spacer()
                        Text(relation.kind == "mute" ? "مكتوم" : "محظور")
                            .font(.caption).foregroundColor(.secondary)
                        Button("إلغاء") { Task { await remove(relation) } }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle("الخصوصية")
        .task { await load() }
    }

    @MainActor
    private func load() async {
        relations = (try? await session.api.privacy()) ?? []
        isLoading = false
    }

    @MainActor
    private func remove(_ relation: PrivacyRelation) async {
        do {
            try await session.api.setRelation(code: relation.publicCode, kind: relation.kind, enabled: false)
            await load()
        } catch { session.alertMessage = error.localizedDescription }
    }
}
