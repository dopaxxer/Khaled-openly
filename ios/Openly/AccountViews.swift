import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: AppSession
    @State private var query = ""
    @State private var result: SearchResponse?
    @State private var isLoading = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ScreenHeader("بحث", subtitle: "ابحث عن الكلمات العامة أو أكواد الهوية.")

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(OpenlyTheme.subtle)
                        TextField("كلمات أو كود هوية", text: $query)
                            .font(.system(size: 15))
                            .foregroundStyle(OpenlyTheme.foreground)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if !query.isEmpty {
                            Button { query = ""; result = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(OpenlyTheme.subtle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(OpenlyTheme.surface)
                    .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                    .clipShape(Capsule())
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)

                    if isLoading {
                        ProgressView("جارِ البحث")
                            .controlSize(.small)
                            .foregroundStyle(OpenlyTheme.muted)
                            .padding(.top, 40)
                    } else if let result {
                        if !result.users.isEmpty {
                            SectionLabel("الهويات")
                            ForEach(result.users) { user in
                                NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                                    HStack {
                                        IdentityBadge(code: user.publicCode, color: user.identityColor)
                                        Spacer()
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(OpenlyTheme.subtle)
                                    }
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 56)
                                    .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !result.posts.isEmpty {
                            SectionLabel("المنشورات")
                            ForEach(result.posts) { post in PostCard(post: post) }
                        }
                        if result.users.isEmpty && result.posts.isEmpty {
                            EmptyState(icon: "magnifyingglass", title: "لا توجد نتائج", message: "جرّب كلمة أو كودًا مختلفًا.")
                        }
                    } else {
                        EmptyState(icon: "text.magnifyingglass", title: "ابحث في Openly", message: "ابدأ بكتابة كلمة أو كود هوية في الأعلى.")
                    }
                }
            }
            .background(OpenlyTheme.surface)
            .toolbar(.hidden, for: .navigationBar)
        }
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

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OpenlyTheme.muted)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 28)
        .padding(.bottom, 10)
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
                    .background(OpenlyTheme.surface)
            } else if isLoading && response == nil {
                ProgressView("جارِ تحميل الإشعارات")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OpenlyTheme.surface)
            } else if let items = response?.items, !items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            NavigationLink(destination: destination(for: item)) {
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle().fill(OpenlyTheme.surfaceSoft)
                                        Circle()
                                            .fill(Color(hex: item.actorColor) ?? OpenlyTheme.accent)
                                            .frame(width: 9, height: 9)
                                    }
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(OpenlyTheme.line, lineWidth: 1))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(notificationText(item))
                                            .font(.system(size: 15, weight: item.readAt == nil ? .semibold : .regular))
                                            .foregroundStyle(OpenlyTheme.foreground)
                                            .multilineTextAlignment(.leading)
                                        Text(OpenlyDate.relative(item.createdAt))
                                            .font(.system(size: 11))
                                            .foregroundStyle(OpenlyTheme.subtle)
                                    }
                                    Spacer(minLength: 8)
                                    if item.readAt == nil {
                                        Circle().fill(OpenlyTheme.accent).frame(width: 7, height: 7).padding(.top, 7)
                                    }
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(OpenlyTheme.subtle)
                                        .padding(.top, 6)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .background(item.readAt == nil ? OpenlyTheme.accentSoft : OpenlyTheme.surface)
                                .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(OpenlyTheme.surface)
                .refreshable { await load() }
            } else {
                EmptyState(icon: "bell.slash", title: "لا توجد إشعارات", message: "ستظهر هنا الإعجابات والردود المرتبطة بك.")
                    .background(OpenlyTheme.surface)
            }
        }
        .navigationTitle("الإشعارات")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { if session.user != nil { await load() } }
    }

    @ViewBuilder
    private func destination(for item: NotificationItem) -> some View {
        if let id = item.postId { PostDetailView(postID: id) }
        else { EmptyState(icon: "bell", title: "إشعار", message: notificationText(item)).background(OpenlyTheme.surface) }
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
            session.unreadCount = 0
        } catch { session.alertMessage = error.localizedDescription }
        isLoading = false
    }
}

struct AccountView: View {
    @EnvironmentObject private var session: AppSession
    @State private var followersCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ScreenHeader("حسابي", subtitle: session.user == nil ? "سجّل الدخول للوصول إلى هويتك وإعداداتك." : "هويتك وكلماتك وإعداداتك في مكان واحد.")
                    if let user = session.user {
                        VStack(alignment: .leading, spacing: 14) {
                            IdentityBadge(code: user.publicCode, color: user.identityColor, large: true)
                            if let status = user.status, !status.isEmpty {
                                Text(status)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(OpenlyTheme.foreground)
                                    .lineSpacing(5)
                            }
                            if let bio = user.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 14))
                                    .foregroundStyle(OpenlyTheme.muted)
                                    .lineSpacing(5)
                            }
                            Text("انضم في \(OpenlyDate.short(user.createdAt))")
                                .font(.system(size: 12))
                                .foregroundStyle(OpenlyTheme.subtle)

                            HStack(spacing: 12) {
                                StatCard(title: "المتابعون", value: "\(followersCount)")
                                StatCard(title: "الهوية", value: user.publicCode)
                            }
                            .padding(.top, 6)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 26)

                        SectionLabel("المحتوى")
                        AccountLink(title: "كتاباتي", icon: "text.bubble", destination: UserPostsView(code: user.publicCode))
                        AccountLink(title: "المحفوظات", icon: "bookmark", destination: BookmarksView())
                        AccountLink(title: "الأكواد التي أتابعها", icon: "person.2", destination: FollowingView())

                        SectionLabel("الحساب")
                        AccountLink(title: "الخصوصية", icon: "hand.raised", destination: PrivacyView())
                        AccountLink(title: "المظهر", icon: "circle.lefthalf.filled", destination: AppearanceView())

                        Button {
                            Task { await session.logout() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 17))
                                Text("تسجيل الخروج").font(.system(size: 14, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(OpenlyTheme.danger)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 58)
                            .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 30)
                    } else {
                        LoginView(embedded: true)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 40)
                    }
                }
            }
            .background(OpenlyTheme.surface)
            .toolbar(.hidden, for: .navigationBar)
            .task { if session.user != nil { followersCount = (try? await session.api.followersCount()) ?? 0 } }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(OpenlyTheme.muted)
            Text(value)
                .font(.system(size: 23, weight: .bold, design: title == "الهوية" ? .monospaced : .default))
                .foregroundStyle(OpenlyTheme.foreground)
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenlyTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenlyTheme.line, lineWidth: 1))
    }
}

private struct AccountLink<Destination: View>: View {
    let title: String
    let icon: String
    let destination: Destination

    init(title: String, icon: String, destination: Destination) {
        self.title = title
        self.icon = icon
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(OpenlyTheme.muted)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OpenlyTheme.foreground)
                Spacer()
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OpenlyTheme.subtle)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
    }
}

struct AppearanceView: View {
    @AppStorage("openly.appearance") private var appearance = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader("المظهر", subtitle: "اختر مظهر التطبيق. يتطابق خيار النظام مع إعداد جهازك.")
                VStack(spacing: 0) {
                    appearanceRow("النظام", value: "system", icon: "iphone")
                    appearanceRow("فاتح", value: "light", icon: "sun.max")
                    appearanceRow("داكن", value: "dark", icon: "moon")
                }
                .background(OpenlyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenlyTheme.line, lineWidth: 1))
                .padding(.horizontal, 18)
            }
        }
        .background(OpenlyTheme.background)
        .navigationTitle("المظهر")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceRow(_ title: String, value: String, icon: String) -> some View {
        Button { appearance = value } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(OpenlyTheme.muted)
                Text(title).foregroundStyle(OpenlyTheme.foreground)
                Spacer()
                if appearance == value {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OpenlyTheme.accent)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 56)
            .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: value == "system" ? 0 : 0.5) }
        }
        .buttonStyle(.plain)
    }
}

struct LoginRequiredView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(OpenlyTheme.muted)
                .multilineTextAlignment(.center)
            NavigationLink(destination: LoginView()) {
                Text("تسجيل الدخول")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(OpenlyPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var showRegister = false
    var embedded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !embedded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("مرحبًا بعودتك")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(OpenlyTheme.foreground)
                        Text("ادخل إلى هويتك وكلماتك.")
                            .font(.system(size: 14))
                            .foregroundStyle(OpenlyTheme.muted)
                    }
                    .padding(.bottom, 42)
                }

                VStack(alignment: .leading, spacing: 22) {
                    OpenlyFieldLabel("البريد الإلكتروني") {
                        TextField("name@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    OpenlyFieldLabel("كلمة المرور") {
                        SecureField("••••••••", text: $password)
                            .textContentType(.password)
                            .environment(\.layoutDirection, .leftToRight)
                    }

                    Button { Task { await login() } } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView().tint(.white).controlSize(.small) }
                            else { Text("تسجيل الدخول") }
                            Spacer()
                        }
                    }
                    .buttonStyle(OpenlyPrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || isSubmitting)
                    .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

                    Button("ليس لديك حساب؟ أنشئ هويتك") { showRegister = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OpenlyTheme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, embedded ? 0 : 22)
            .padding(.top, embedded ? 8 : 58)
            .padding(.bottom, 30)
        }
        .background(OpenlyTheme.surface)
        .navigationTitle(embedded ? "" : "تسجيل الدخول")
        .navigationBarTitleDisplayMode(.inline)
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

private struct OpenlyFieldLabel<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OpenlyTheme.foreground)
            content
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(OpenlyTheme.surface)
                .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                .clipShape(Capsule())
        }
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
        NavigationStack {
            ScrollView {
                if let verificationEmail {
                    VerificationView(email: verificationEmail) {
                        Task { await session.refresh(); dismiss() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ScreenHeader("أنشئ هويتك", subtitle: "سنمنحك كودًا ولونًا ثابتين؛ لا اسم عرض ولا صورة شخصية.")
                        VStack(spacing: 22) {
                            OpenlyFieldLabel("البريد الإلكتروني") {
                                TextField("name@example.com", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            OpenlyFieldLabel("كلمة المرور") {
                                SecureField("8 أحرف على الأقل", text: $password)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            OpenlyFieldLabel("تأكيد كلمة المرور") {
                                SecureField("أعد كتابة كلمة المرور", text: $confirmation)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            Button { Task { await register() } } label: {
                                HStack {
                                    Spacer()
                                    if isSubmitting { ProgressView().tint(.white).controlSize(.small) }
                                    else { Text("إنشاء الحساب") }
                                    Spacer()
                                }
                            }
                            .buttonStyle(OpenlyPrimaryButtonStyle())
                            .disabled(!formIsValid || isSubmitting)
                            .opacity(formIsValid ? 1 : 0.5)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(OpenlyTheme.background)
            .navigationTitle("حساب جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
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
        VStack(alignment: .leading, spacing: 20) {
            Text("تحقق من بريدك")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(OpenlyTheme.foreground)
            Text("أرسلنا كودًا مكوّنًا من 6 أرقام إلى \(email). أدخله هنا لإكمال إنشاء حسابك.")
                .font(.system(size: 14))
                .foregroundStyle(OpenlyTheme.muted)
                .lineSpacing(5)
            TextField("000000", text: $token)
                .keyboardType(.numberPad)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .tracking(7)
                .environment(\.layoutDirection, .leftToRight)
                .frame(height: 54)
                .background(OpenlyTheme.surface)
                .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                .onChange(of: token) { value in token = String(value.filter(\.isNumber).prefix(6)) }
            Button("تأكيد") { Task { await verify() } }
                .frame(maxWidth: .infinity)
                .buttonStyle(OpenlyPrimaryButtonStyle())
                .disabled(token.count != 6 || isSubmitting)
                .opacity(token.count == 6 ? 1 : 0.5)
            Button("لم يصلك الكود؟ إعادة الإرسال") { Task { await resend() } }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OpenlyTheme.muted)
                .frame(maxWidth: .infinity)
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(OpenlyTheme.success)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 56)
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
            status = "أُرسل كود جديد إلى بريدك."
        } catch { session.alertMessage = error.localizedDescription }
    }
}

struct UserProfileView: View {
    @EnvironmentObject private var session: AppSession
    let code: String
    @State private var user: UserSummary?
    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var relationBusy = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let user {
                    VStack(alignment: .leading, spacing: 14) {
                        IdentityBadge(code: user.publicCode, color: user.identityColor, large: true)
                        if let status = user.status, !status.isEmpty {
                            Text(status).font(.system(size: 16)).foregroundStyle(OpenlyTheme.foreground).lineSpacing(5)
                        }
                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio).font(.system(size: 14)).foregroundStyle(OpenlyTheme.muted).lineSpacing(5)
                        }
                        Text("انضم في \(OpenlyDate.short(user.createdAt))")
                            .font(.system(size: 12)).foregroundStyle(OpenlyTheme.subtle)

                        if user.isSelf != true && session.user != nil {
                            HStack(spacing: 10) {
                                if user.viewerIsFollowing == true {
                                    Button("إلغاء المتابعة") {
                                        Task { await toggleRelation("follow", current: true) }
                                    }
                                    .buttonStyle(OpenlySecondaryButtonStyle())
                                } else {
                                    Button("متابعة") {
                                        Task { await toggleRelation("follow", current: false) }
                                    }
                                    .buttonStyle(OpenlyPrimaryButtonStyle())
                                }
                                Button(user.viewerHasMuted == true ? "إلغاء الكتم" : "كتم") {
                                    Task { await toggleRelation("mute", current: user.viewerHasMuted == true) }
                                }
                                .buttonStyle(OpenlySecondaryButtonStyle())
                                Button(user.viewerHasBlocked == true ? "إلغاء الحظر" : "حظر") {
                                    Task { await toggleRelation("block", current: user.viewerHasBlocked == true) }
                                }
                                .buttonStyle(OpenlySecondaryButtonStyle())
                            }
                            .disabled(relationBusy)
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 26)

                    SectionLabel("المنشورات")
                    if posts.isEmpty && !isLoading {
                        EmptyState(icon: "text.bubble", title: "لا توجد منشورات", message: "لم ينشر هذا الحساب شيئًا بعد.")
                    } else {
                        ForEach(posts) { PostCard(post: $0) }
                    }
                } else if isLoading {
                    ProgressView("جارِ التحميل").padding(.top, 60)
                } else {
                    EmptyState(icon: "person.slash", title: "الحساب غير موجود", message: "تعذر العثور على هذا الكود.")
                }
            }
        }
        .background(OpenlyTheme.surface)
        .navigationTitle(code)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            async let userValue = session.api.user(code: code)
            async let postsValue = session.api.feed(author: code)
            user = try await userValue
            posts = try await postsValue.items
        } catch { session.alertMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func toggleRelation(_ kind: String, current: Bool) async {
        relationBusy = true
        do {
            try await session.api.setRelation(code: code, kind: kind, enabled: !current)
            user = try await session.api.user(code: code)
        } catch { session.alertMessage = error.localizedDescription }
        relationBusy = false
    }
}

struct UserPostsView: View {
    @EnvironmentObject private var session: AppSession
    let code: String
    @State private var posts: [Post] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading { ProgressView("جارِ التحميل").padding(.top, 60) }
                else if posts.isEmpty { EmptyState(icon: "text.bubble", title: "لا توجد منشورات", message: "لا توجد كتابات هنا بعد.") }
                else { ForEach(posts) { PostCard(post: $0) } }
            }
        }
        .background(OpenlyTheme.surface)
        .navigationTitle("الكتابات")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor private func load() async {
        loading = true
        do { posts = try await session.api.feed(author: code).items }
        catch { session.alertMessage = error.localizedDescription }
        loading = false
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var session: AppSession
    @State private var posts: [Post] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading { ProgressView("جارِ التحميل").padding(.top, 60) }
                else if posts.isEmpty { EmptyState(icon: "bookmark", title: "لا توجد محفوظات", message: "المنشورات التي تحفظها ستظهر هنا.") }
                else { ForEach(posts) { PostCard(post: $0) } }
            }
        }
        .background(OpenlyTheme.surface)
        .navigationTitle("المحفوظات")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor private func load() async {
        loading = true
        do { posts = try await session.api.bookmarks() }
        catch { session.alertMessage = error.localizedDescription }
        loading = false
    }
}

struct FollowingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var users: [UserSummary] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading { ProgressView("جارِ التحميل").padding(.top, 60) }
                else if users.isEmpty { EmptyState(icon: "person.2", title: "لا تتابع أحدًا", message: "الأكواد التي تتابعها ستظهر هنا.") }
                else {
                    ForEach(users) { user in
                        NavigationLink(destination: UserProfileView(code: user.publicCode)) {
                            HStack {
                                IdentityBadge(code: user.publicCode, color: user.identityColor)
                                Spacer()
                                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(OpenlyTheme.subtle)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 58)
                            .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(OpenlyTheme.surface)
        .navigationTitle("المتابَعون")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor private func load() async {
        loading = true
        do { users = try await session.api.following() }
        catch { session.alertMessage = error.localizedDescription }
        loading = false
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var session: AppSession
    @State private var relations: [PrivacyRelation] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading { ProgressView("جارِ التحميل").padding(.top, 60) }
                else if relations.isEmpty { EmptyState(icon: "hand.raised", title: "لا توجد قيود", message: "الحسابات المكتومة أو المحظورة ستظهر هنا.") }
                else {
                    ForEach(relations) { relation in
                        HStack(spacing: 12) {
                            IdentityBadge(code: relation.publicCode, color: relation.identityColor)
                            Text(relation.kind == "block" ? "محظور" : "مكتوم")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(OpenlyTheme.muted)
                            Spacer()
                            Button("إلغاء") { Task { await remove(relation) } }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(OpenlyTheme.accent)
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 60)
                        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
                    }
                }
            }
        }
        .background(OpenlyTheme.surface)
        .navigationTitle("الخصوصية")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor private func load() async {
        loading = true
        do { relations = try await session.api.privacy() }
        catch { session.alertMessage = error.localizedDescription }
        loading = false
    }

    @MainActor private func remove(_ relation: PrivacyRelation) async {
        do {
            try await session.api.setRelation(code: relation.publicCode, kind: relation.kind, enabled: false)
            await load()
        } catch { session.alertMessage = error.localizedDescription }
    }
}
