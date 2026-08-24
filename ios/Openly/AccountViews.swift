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
                AppHeader()

                ScrollView {
                    VStack(spacing: 0) {
                        ScreenHeader("بحث", subtitle: "ابحث عن كلمات عامة أو كود هوية.")

                        HStack(spacing: 14) {
                            OpenlyFieldContainer {
                                HStack(spacing: 10) {
                                    TextField("إبحث...", text: $query)
                                        .foregroundColor(OpenlyTheme.ink)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .focused($focused)
                                        .submitLabel(.search)
                                        .onSubmit { Task { await search() } }

                                    if !query.isEmpty {
                                        Button {
                                            query = ""
                                            result = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(OpenlyTheme.subtle)
                                        }
                                    }
                                }
                            }

                            Button {
                                Task { await search() }
                            } label: {
                                if isLoading {
                                    ProgressView().tint(OpenlyTheme.accentForeground)
                                } else {
                                    Text("بحث")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .foregroundColor(OpenlyTheme.accentForeground)
                            .frame(width: 92, height: 56)
                            .background(OpenlyTheme.accentSoft)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 26)

                        if isLoading {
                            ProgressView("جارِ البحث")
                                .tint(OpenlyTheme.accent)
                                .foregroundColor(OpenlyTheme.muted)
                                .padding(.top, 24)
                        } else if let result {
                            SearchResultsView(result: result)
                        }
                    }
                }
                .background(OpenlyTheme.background)
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
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

private struct SearchResultsView: View {
    let result: SearchResponse

    var body: some View {
        LazyVStack(spacing: 0) {
            if result.users.isEmpty && result.posts.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "لا توجد نتائج", message: "جرّب كلمة أو كودًا مختلفًا.")
            }

            if !result.users.isEmpty {
                HStack {
                    Text("الهويات")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(OpenlyTheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }

                ForEach(result.users) { user in
                    NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                        HStack {
                            IdentityBadge(code: user.publicCode, color: user.identityColor)
                            Spacer()
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(OpenlyTheme.subtle)
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 62)
                        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !result.posts.isEmpty {
                HStack {
                    Text("المنشورات")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(OpenlyTheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }

                ForEach(result.posts) { post in
                    PostCard(post: post)
                }
            }
        }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var response: NotificationResponse?
    @State private var isLoading = false

    var body: some View {
        Group {
            if session.user == nil {
                LoginRequiredView(message: "سجّل الدخول لرؤية الإشعارات.")
            } else if isLoading && response == nil {
                ProgressView("جارِ تحميل الإشعارات")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
            } else if let items = response?.items, !items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            NavigationLink(destination: destination(for: item)) {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color(hex: item.actorColor) ?? OpenlyTheme.accent)
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(notificationText(item))
                                            .font(.system(size: 15, weight: item.readAt == nil ? .semibold : .regular))
                                            .foregroundColor(OpenlyTheme.ink)
                                        Text(OpenlyDate.relative(item.createdAt))
                                            .font(.system(size: 12))
                                            .foregroundColor(OpenlyTheme.subtle)
                                    }
                                    Spacer()
                                    if item.readAt == nil {
                                        Circle().fill(OpenlyTheme.accent).frame(width: 7, height: 7)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 18)
                                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { await load() }
            } else {
                EmptyState(icon: "bell.slash", title: "لا توجد إشعارات", message: "ستظهر هنا الإعجابات والردود المرتبطة بك.")
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الإشعارات")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { if session.user != nil { await load() } }
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
            VStack(spacing: 0) {
                AppHeader()

                if let user = session.user {
                    ScrollView {
                        VStack(spacing: 0) {
                            VStack(spacing: 13) {
                                IdentityAvatar(code: user.publicCode, color: user.identityColor, size: 66)
                                Text(user.publicCode)
                                    .font(.system(size: 25, weight: .bold, design: .monospaced))
                                    .foregroundColor(OpenlyTheme.ink)
                                    .environment(\.layoutDirection, .leftToRight)
                                Text("انضم في \(OpenlyDate.short(user.createdAt))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(OpenlyTheme.subtle)
                                if let bio = user.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.system(size: 15))
                                        .foregroundColor(OpenlyTheme.muted)
                                        .multilineTextAlignment(.center)
                                }
                                Text("\(followersCount) متابع")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(OpenlyTheme.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 34)
                            .padding(.bottom, 30)

                            Rectangle().fill(OpenlyTheme.line).frame(height: 1)

                            NavigationLink(destination: NotificationsView()) {
                                AccountMenuRow(icon: "bell", title: "الإشعارات")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: UserPostsView(code: user.publicCode)) {
                                AccountMenuRow(icon: "text.bubble", title: "كتاباتي")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: BookmarksView()) {
                                AccountMenuRow(icon: "bookmark", title: "المحفوظات")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: FollowingView()) {
                                AccountMenuRow(icon: "person.2", title: "الأكواد التي أتابعها")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: PrivacyView()) {
                                AccountMenuRow(icon: "hand.raised", title: "الخصوصية")
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                Task { await session.logout() }
                            } label: {
                                AccountMenuRow(icon: "rectangle.portrait.and.arrow.right", title: "تسجيل الخروج", danger: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .task { followersCount = (try? await session.api.followersCount()) ?? 0 }
                } else {
                    LoginRequiredView(message: "سجّل الدخول لرؤية حسابك.")
                        .frame(maxHeight: .infinity)
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

private struct AccountMenuRow: View {
    let icon: String
    let title: String
    var danger = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .opacity(danger ? 0 : 1)
        }
        .foregroundColor(danger ? OpenlyTheme.danger : OpenlyTheme.muted)
        .padding(.horizontal, 20)
        .frame(height: 62)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }
}

struct LoginRequiredView: View {
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(message)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .multilineTextAlignment(.center)

            NavigationLink(destination: LoginView()) {
                Text("تسجيل الدخول")
                    .frame(width: 190)
            }
            .buttonStyle(OpenlyPrimaryButtonStyle())
            .frame(width: 190)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(OpenlyTheme.background)
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var showRegister = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandLockup(markSize: 34)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(OpenlyTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .frame(height: 74)
            .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("مرحبًا بعودتك")
                            .font(.system(size: 31, weight: .bold))
                            .foregroundColor(OpenlyTheme.ink)
                        Text("ادخل إلى هويتك وكلماتك.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OpenlyTheme.muted)
                    }
                    .padding(.top, 46)
                    .padding(.bottom, 42)

                    Text("البريد الإلكتروني")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OpenlyTheme.ink)
                        .padding(.bottom, 10)

                    OpenlyFieldContainer {
                        TextField("البريد الإلكتروني", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.bottom, 26)

                    Text("كلمة المرور")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OpenlyTheme.ink)
                        .padding(.bottom, 10)

                    OpenlyFieldContainer {
                        SecureField("كلمة المرور", text: $password)
                            .textContentType(.password)
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.bottom, 26)

                    Button { Task { await login() } } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(OpenlyTheme.accentForeground)
                            } else {
                                Text("تسجيل الدخول")
                            }
                        }
                    }
                    .buttonStyle(OpenlyPrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || isSubmitting)
                    .opacity(email.isEmpty || password.isEmpty ? 0.78 : 1)
                    .padding(.bottom, 28)

                    Button("نسيت كلمة المرور؟") {
                        session.alertMessage = "يمكن إضافة استعادة كلمة المرور عند ربط مسارها بالخادم."
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)

                    Button("ليس لديك حساب؟ أنشئ هويتك") { showRegister = true }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OpenlyTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ScreenHeader("أنشئ هويتك", subtitle: "سيمنحك التطبيق كودًا ولونًا ثابتين دون اسم عرض أو صورة شخصية.")

                            Text("البريد الإلكتروني")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(OpenlyTheme.ink)
                            OpenlyFieldContainer {
                                TextField("البريد الإلكتروني", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(OpenlyTheme.ink)
                            }

                            Text("كلمة المرور")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(OpenlyTheme.ink)
                            OpenlyFieldContainer {
                                SecureField("8 أحرف على الأقل", text: $password)
                                    .foregroundColor(OpenlyTheme.ink)
                            }

                            Text("تأكيد كلمة المرور")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(OpenlyTheme.ink)
                            OpenlyFieldContainer {
                                SecureField("أعد كتابة كلمة المرور", text: $confirmation)
                                    .foregroundColor(OpenlyTheme.ink)
                            }

                            Button { Task { await register() } } label: {
                                if isSubmitting {
                                    ProgressView().tint(OpenlyTheme.accentForeground)
                                } else {
                                    Text("إنشاء الحساب")
                                }
                            }
                            .buttonStyle(OpenlyPrimaryButtonStyle())
                            .disabled(!formIsValid || isSubmitting)
                            .opacity(formIsValid ? 1 : 0.65)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationTitle("حساب جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundColor(OpenlyTheme.accent)
            Text("تحقق من بريدك")
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(OpenlyTheme.ink)
            Text("أرسلنا كودًا من 6 أرقام إلى\n\(email)")
                .multilineTextAlignment(.center)
                .foregroundColor(OpenlyTheme.muted)

            OpenlyFieldContainer {
                TextField("000000", text: $token)
                    .keyboardType(.numberPad)
                    .font(.system(size: 25, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundColor(OpenlyTheme.ink)
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: token) { value in
                        token = String(value.filter(\.isNumber).prefix(6))
                    }
            }

            Button("تأكيد الكود") { Task { await verify() } }
                .buttonStyle(OpenlyPrimaryButtonStyle())
                .disabled(token.count != 6 || isSubmitting)

            Button("إعادة إرسال الكود") { Task { await resend() } }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(OpenlyTheme.muted)
            }
        }
        .padding(24)
        .background(OpenlyTheme.background.ignoresSafeArea())
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
        ScrollView {
            LazyVStack(spacing: 0) {
                if let user {
                    VStack(spacing: 12) {
                        IdentityAvatar(code: user.publicCode, color: user.identityColor, size: 62)
                        Text(user.publicCode)
                            .font(.system(size: 25, weight: .bold, design: .monospaced))
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .foregroundColor(OpenlyTheme.muted)
                                .multilineTextAlignment(.center)
                        }
                        Text("انضم في \(OpenlyDate.short(user.createdAt))")
                            .font(.caption)
                            .foregroundColor(OpenlyTheme.subtle)

                        if user.isSelf != true {
                            HStack {
                                Button(user.viewerIsFollowing == true ? "إلغاء المتابعة" : "متابعة") {
                                    Task { await setRelation("follow", enabled: user.viewerIsFollowing != true) }
                                }
                                .buttonStyle(OpenlySecondaryButtonStyle())

                                Menu {
                                    Button(user.viewerHasMuted == true ? "إلغاء الكتم" : "كتم") {
                                        Task { await setRelation("mute", enabled: user.viewerHasMuted != true) }
                                    }
                                    Button(user.viewerHasBlocked == true ? "إلغاء الحظر" : "حظر", role: .destructive) {
                                        Task { await setRelation("block", enabled: user.viewerHasBlocked != true) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundColor(OpenlyTheme.muted)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                    .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }

                    if posts.isEmpty {
                        EmptyState(icon: "text.bubble", title: "لا توجد منشورات", message: "لا توجد كتابات لهذه الهوية بعد.")
                    } else {
                        ForEach(posts) { post in PostCard(post: post) }
                    }
                } else if isLoading {
                    ProgressView().tint(OpenlyTheme.accent).padding(.top, 50)
                }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle(code)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(posts) { PostCard(post: $0) }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("كتاباتي")
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { posts = (try? await session.api.feed(author: code))?.items ?? [] }
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var session: AppSession
    @State private var posts: [Post] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(OpenlyTheme.accent)
            } else if posts.isEmpty {
                EmptyState(icon: "bookmark", title: "لا توجد محفوظات", message: "المنشورات التي تحفظها ستظهر هنا.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { PostCard(post: $0) }
                    }
                }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("المحفوظات")
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
            if isLoading {
                ProgressView().tint(OpenlyTheme.accent)
            } else if users.isEmpty {
                EmptyState(icon: "person.2", title: "لا تتابع أي كود", message: "ستظهر هنا الهويات التي تتابعها.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(users) { user in
                            NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                                HStack {
                                    IdentityBadge(code: user.publicCode, color: user.identityColor)
                                    Spacer()
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(OpenlyTheme.subtle)
                                }
                                .padding(.horizontal, 20)
                                .frame(height: 62)
                                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("المتابَعون")
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
            if isLoading {
                ProgressView().tint(OpenlyTheme.accent)
            } else if relations.isEmpty {
                EmptyState(icon: "hand.raised", title: "لا توجد علاقات خصوصية", message: "الحسابات المكتومة والمحظورة ستظهر هنا.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(relations) { relation in
                            HStack {
                                IdentityBadge(code: relation.publicCode, color: relation.identityColor)
                                Spacer()
                                Text(relation.kind == "mute" ? "مكتوم" : "محظور")
                                    .font(.caption)
                                    .foregroundColor(OpenlyTheme.subtle)
                                Button("إلغاء") { Task { await remove(relation) } }
                                    .foregroundColor(OpenlyTheme.accent)
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 62)
                            .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
                        }
                    }
                }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الخصوصية")
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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