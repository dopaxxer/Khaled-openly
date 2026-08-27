import SwiftUI
import AuthenticationServices
import Combine
import CryptoKit
import GoogleSignIn
import Security
import UIKit

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
        case "mention":
            return item.commentId == nil
                ? "أشار إليك \(actor) في منشور"
                : "أشار إليك \(actor) في تعليق"
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

                            NavigationLink(destination: SettingsView()) {
                                AccountMenuRow(icon: "paintpalette", title: "الثيمات")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: InterestPreferencesView()) {
                                AccountMenuRow(icon: "sparkles", title: "اهتماماتي")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: MusicPreferencesView()) {
                                AccountMenuRow(icon: "music.note", title: "ذوقي الموسيقي")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: MusicVisibilitySettingsView()) {
                                AccountMenuRow(icon: "eye", title: "ما يظهر في ملفي")
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

private let authCountryDialCodes: [(String, String)] = [
    ("ألمانيا", "+49"),
    ("السعودية", "+966"),
    ("اليمن", "+967"),
    ("الإمارات", "+971"),
    ("مصر", "+20"),
    ("العراق", "+964"),
    ("الأردن", "+962"),
    ("الكويت", "+965"),
    ("قطر", "+974"),
    ("البحرين", "+973"),
    ("عُمان", "+968"),
    ("تركيا", "+90"),
    ("المملكة المتحدة", "+44"),
    ("فرنسا", "+33"),
    ("إيطاليا", "+39"),
    ("إسبانيا", "+34"),
    ("هولندا", "+31"),
    ("السويد", "+46"),
    ("الولايات المتحدة / كندا", "+1"),
    ("أخرى — أدخل الرقم كاملًا", "")
]

private func authSHA256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func authSecureNonce(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length

    while remaining > 0 {
        var random: UInt8 = 0
        guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        if random < charset.count {
            result.append(charset[Int(random)])
            remaining -= 1
        }
    }
    return result
}

@MainActor
private func authPresentingViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let window = scenes
        .flatMap(\.windows)
        .first(where: { $0.isKeyWindow }),
          var controller = window.rootViewController else { return nil }

    while let presented = controller.presentedViewController {
        controller = presented
    }
    if let navigation = controller as? UINavigationController {
        return navigation.visibleViewController ?? navigation
    }
    if let tab = controller as? UITabBarController {
        return tab.selectedViewController ?? tab
    }
    return controller
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @State private var method = "email"
    @State private var step = "entry"
    @State private var email = ""
    @State private var countryCode = "+49"
    @State private var phone = ""
    @State private var verificationTarget = ""
    @State private var maskedTarget = ""
    @State private var token = ""
    @State private var isSubmitting = false
    @State private var isResending = false
    @State private var resendSeconds = 0
    @State private var status: String?
    @State private var inlineError: String?
    @State private var currentAppleNonce: String?
    @State private var capabilities = AuthCapabilities(
        email: true,
        emailOtp: false,
        emailMode: "link",
        phone: false,
        google: false,
        apple: false
    )

    private let secondTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandLockup(markSize: 38)
                    Spacer()
                }
                .padding(.bottom, 42)

                if step == "otp" {
                    otpContent
                } else {
                    entryContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 50)
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { await loadCapabilities() }
        .onReceive(secondTicker) { _ in
            if resendSeconds > 0 { resendSeconds -= 1 }
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        Text("Openly")
            .font(.system(size: 34, weight: .bold))
            .foregroundColor(OpenlyTheme.ink)
        Text("دخول بسيط وآمن. لا تحتاج إلى كلمة مرور.")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(OpenlyTheme.muted)
            .padding(.top, 8)
            .padding(.bottom, 30)

        if capabilities.apple {
            SignInWithAppleButton(.continue) { request in
                let nonce = UUID().uuidString + UUID().uuidString
                currentAppleNonce = nonce
                request.requestedScopes = [.email]
                request.nonce = authSHA256(nonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isSubmitting)
        }

        if capabilities.google {
            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Text("G").font(.system(size: 18, weight: .bold))
                    Text("Continue with Google").font(.system(size: 16, weight: .semibold))
                }
            }
            .buttonStyle(OpenlySecondaryButtonStyle())
            .disabled(isSubmitting)
            .padding(.top, capabilities.apple ? 12 : 0)
        }

        if capabilities.apple || capabilities.google {
            HStack {
                Rectangle().fill(OpenlyTheme.line).frame(height: 1)
                Text("أو")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
                Rectangle().fill(OpenlyTheme.line).frame(height: 1)
            }
            .padding(.vertical, 26)
        }

        if method == "email" && capabilities.emailOtp {
            Text("البريد الإلكتروني")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
                .padding(.bottom, 10)
            OpenlyFieldContainer {
                TextField("example@email.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(OpenlyTheme.ink)
                    .environment(\.layoutDirection, .leftToRight)
            }

            authMessages

            Button { Task { await requestCode() } } label: {
                if isSubmitting {
                    ProgressView().tint(OpenlyTheme.accentForeground)
                } else {
                    Text("متابعة")
                }
            }
            .buttonStyle(OpenlyPrimaryButtonStyle())
            .disabled(isSubmitting || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 20)

            if capabilities.phone {
                Button("المتابعة برقم الهاتف") {
                    method = "phone"
                    inlineError = nil
                    status = nil
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            }
        } else if method == "phone" && capabilities.phone {
            Text("رمز الدولة")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
                .padding(.bottom, 10)
            OpenlyFieldContainer {
                Picker("رمز الدولة", selection: $countryCode) {
                    ForEach(authCountryDialCodes, id: \.0) { item in
                        Text(item.1.isEmpty ? item.0 : "\(item.0)  \(item.1)")
                            .tag(item.1)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("رقم الهاتف")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
                .padding(.top, 20)
                .padding(.bottom, 10)
            OpenlyFieldContainer {
                TextField(countryCode.isEmpty ? "+491234567890" : "1234567890", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .foregroundColor(OpenlyTheme.ink)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Text("يُرسل الرقم إلى Supabase بصيغة E.164.")
                .font(.system(size: 12))
                .foregroundColor(OpenlyTheme.subtle)
                .padding(.top, 8)

            authMessages

            Button { Task { await requestCode() } } label: {
                if isSubmitting {
                    ProgressView().tint(OpenlyTheme.accentForeground)
                } else {
                    Text("إرسال رمز SMS")
                }
            }
            .buttonStyle(OpenlyPrimaryButtonStyle())
            .disabled(isSubmitting || phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 20)

            if capabilities.emailOtp {
                Button("العودة للبريد الإلكتروني") {
                    method = "email"
                    inlineError = nil
                    status = nil
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            }
        } else if !capabilities.apple && !capabilities.google {
            VStack(alignment: .leading, spacing: 14) {
                Text("تسجيل الدخول داخل التطبيق غير متاح حاليًا.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                Text("لن نعرض أزرارًا لا تعمل. يمكنك استخدام تسجيل الدخول بالبريد على الموقع، وستظهر الطرق الأصلية هنا تلقائيًا عند تفعيلها.")
                    .font(.system(size: 14))
                    .foregroundColor(OpenlyTheme.muted)
                Link("فتح openly.ink", destination: URL(string: "https://www.openly.ink/login")!)
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(18)
            .background(OpenlyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var otpContent: some View {
        Image(systemName: method == "phone" ? "message.badge" : "envelope.badge")
            .font(.system(size: 42))
            .foregroundColor(OpenlyTheme.accent)
            .padding(.bottom, 18)
        Text("أدخل رمز التحقق")
            .font(.system(size: 29, weight: .bold))
            .foregroundColor(OpenlyTheme.ink)
        Text("أرسلنا رمزًا من 6 أرقام إلى \(maskedTarget).")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(OpenlyTheme.muted)
            .padding(.top, 8)
            .padding(.bottom, 28)

        OpenlyFieldContainer {
            TextField("000000", text: $token)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 25, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundColor(OpenlyTheme.ink)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: token) { value in
                    token = String(value.filter(\.isNumber).prefix(6))
                }
        }

        authMessages

        Button { Task { await verifyCode() } } label: {
            if isSubmitting {
                ProgressView().tint(OpenlyTheme.accentForeground)
            } else {
                Text("تأكيد والدخول")
            }
        }
        .buttonStyle(OpenlyPrimaryButtonStyle())
        .disabled(isSubmitting || token.count != 6)
        .padding(.top, 20)

        Button {
            Task { await resendCode() }
        } label: {
            if isResending {
                Text("جارِ الإرسال…")
            } else if resendSeconds > 0 {
                Text("إعادة الإرسال بعد \(resendSeconds)ث")
            } else {
                Text("إعادة إرسال الكود")
            }
        }
        .buttonStyle(OpenlySecondaryButtonStyle())
        .disabled(isResending || resendSeconds > 0)
        .padding(.top, 12)

        Button(method == "phone" ? "تغيير رقم الهاتف" : "تغيير البريد الإلكتروني") {
            step = "entry"
            token = ""
            inlineError = nil
            status = nil
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(OpenlyTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    @ViewBuilder
    private var authMessages: some View {
        if let inlineError {
            Text(inlineError)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OpenlyTheme.danger)
                .padding(.top, 12)
                .accessibilityLabel("خطأ: \(inlineError)")
        }
        if let status {
            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .padding(.top, 12)
        }
    }

    private var normalizedPhone: String {
        let compact = phone
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        if countryCode.isEmpty {
            if compact.hasPrefix("+") {
                return "+" + String(compact.dropFirst().filter(\.isNumber))
            }
            return String(compact.filter(\.isNumber))
        }
        return countryCode + String(compact.filter(\.isNumber))
    }

    @MainActor
    private func loadCapabilities() async {
        do {
            let value = try await session.api.authCapabilities()
            capabilities = value
            if !value.emailOtp && value.phone {
                method = "phone"
            } else if !value.phone {
                method = "email"
            }
        } catch {
            // Fail closed: unavailable providers stay hidden.
        }
    }

    @MainActor
    private func requestCode() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        inlineError = nil
        status = nil
        do {
            let response: OTPRequestResponse
            if method == "phone" {
                response = try await session.requestOTP(method: "phone", phone: normalizedPhone)
                verificationTarget = normalizedPhone
            } else {
                let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                response = try await session.requestOTP(method: "email", email: value)
                verificationTarget = value
            }
            maskedTarget = response.target
            resendSeconds = response.cooldownSeconds
            if response.delivery == "link" {
                inlineError = "تسجيل البريد داخل التطبيق يحتاج OTP. استخدم openly.ink مؤقتًا."
                step = "entry"
            } else {
                step = "otp"
            }
        } catch {
            inlineError = error.localizedDescription
        }
        isSubmitting = false
    }

    @MainActor
    private func verifyCode() async {
        guard !isSubmitting, token.count == 6 else { return }
        isSubmitting = true
        inlineError = nil
        do {
            try await session.verifyOTP(method: method, target: verificationTarget, token: token)
        } catch {
            inlineError = error.localizedDescription
        }
        isSubmitting = false
    }

    @MainActor
    private func resendCode() async {
        guard !isResending, resendSeconds == 0 else { return }
        isResending = true
        inlineError = nil
        status = nil
        do {
            let response = method == "phone"
                ? try await session.requestOTP(method: "phone", phone: verificationTarget)
                : try await session.requestOTP(method: "email", email: verificationTarget)
            maskedTarget = response.target
            resendSeconds = response.cooldownSeconds
            status = "أُرسل كود جديد."
        } catch {
            inlineError = error.localizedDescription
        }
        isResending = false
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            inlineError = "تعذر إكمال تسجيل الدخول بحساب Apple."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentAppleNonce else {
                inlineError = "تعذر قراءة بيانات Apple الآمنة."
                return
            }
            Task { @MainActor in
                isSubmitting = true
                inlineError = nil
                do {
                    try await session.signInWithNativeToken(provider: "apple", idToken: idToken, nonce: nonce)
                } catch {
                    inlineError = error.localizedDescription
                }
                isSubmitting = false
            }
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        guard !isSubmitting else { return }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty,
              !clientID.contains("$("),
              let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
              !serverClientID.isEmpty,
              !serverClientID.contains("$(") else {
            inlineError = "Google Sign-In يحتاج إعدادات OAuth كاملة للتطبيق والخادم."
            return
        }
        guard let presenter = authPresentingViewController() else {
            inlineError = "تعذر فتح نافذة Google."
            return
        }

        isSubmitting = true
        inlineError = nil
        do {
            let nonce = authSecureNonce()
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: clientID,
                serverClientID: serverClientID
            )
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw APIError.server("لم يرجع Google رمز هوية صالحًا.")
            }
            try await session.signInWithNativeToken(
                provider: "google",
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                nonce: nonce
            )
        } catch {
            let nsError = error as NSError
            if nsError.code != -5 {
                inlineError = error.localizedDescription
            }
        }
        isSubmitting = false
    }
}

private let passwordMinimumLength = 12

private func passwordIsStrong(_ value: String) -> Bool {
    value.count >= passwordMinimumLength && value.count <= 128 &&
        value.contains(where: \.isLetter) && value.contains(where: \.isNumber)
}

struct ForgotPasswordView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var isSubmitting = false
    @State private var sent = false

    init(initialEmail: String = "") {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                if sent {
                    EmptyState(
                        icon: "envelope.badge",
                        title: "تحقق من بريدك",
                        message: "إذا كان هناك حساب بهذا البريد، أرسلنا رابطًا آمنًا لاختيار كلمة مرور جديدة."
                    )
                    Button("إغلاق") { dismiss() }
                        .buttonStyle(OpenlyPrimaryButtonStyle())
                        .padding(.horizontal, 24)
                } else {
                    ScreenHeader("استعادة كلمة المرور", subtitle: "أدخل البريد المرتبط بحسابك وسنرسل لك رابط الاستعادة.")
                    OpenlyFieldContainer {
                        TextField("البريد الإلكتروني", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.horizontal, 20)

                    Button { Task { await submit() } } label: {
                        if isSubmitting {
                            ProgressView().tint(OpenlyTheme.accentForeground)
                        } else {
                            Text("إرسال رابط الاستعادة")
                        }
                    }
                    .buttonStyle(OpenlyPrimaryButtonStyle())
                    .disabled(!email.contains("@") || isSubmitting)
                    .padding(.horizontal, 20)
                    Spacer()
                }
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationTitle("استعادة الحساب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        do {
            try await session.api.requestPasswordReset(email: email)
            sent = true
        } catch {
            session.alertMessage = error.localizedDescription
        }
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
                                SecureField("12 حرفًا على الأقل، مع حرف ورقم", text: $password)
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
        email.contains("@") && passwordIsStrong(password) && password == confirmation
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
    @State private var interests: PublicInterestProfile?
    @State private var music: PublicMusicProfile?
    @State private var isLoading = true
    @State private var relationBusy = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let user {
                    profileHeader(user)

                    if let interests, !interests.items.isEmpty {
                        NativePublicInterestSection(profile: interests)
                    }

                    if let music {
                        NativePublicMusicSection(music: music)
                    }

                    postsSection
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(OpenlyTheme.accent)
                        Text("جارِ تحميل الملف")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(OpenlyTheme.subtle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    EmptyState(icon: "person.crop.circle.badge.questionmark", title: "تعذر فتح الملف", message: "حاول مرة أخرى.")
                }
            }
            .padding(.bottom, 28)
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: code) { await load() }
    }

    @ViewBuilder
    private func profileHeader(_ user: UserSummary) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                IdentityAvatar(code: user.publicCode, color: user.identityColor, size: 72)

                Text(user.publicCode)
                    .font(.system(size: 27, weight: .bold, design: .monospaced))
                    .tracking(-0.4)
                    .foregroundColor(OpenlyTheme.ink)
                    .environment(\.layoutDirection, .leftToRight)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(OpenlyTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 320)
                        .padding(.top, 2)
                }

                Text("انضم في \(OpenlyDate.short(user.createdAt))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, user.isSelf == true ? 24 : 18)

            if user.isSelf != true {
                HStack(spacing: 10) {
                    Button {
                        Task { await setRelation("follow", enabled: user.viewerIsFollowing != true) }
                    } label: {
                        Text(user.viewerIsFollowing == true ? "إلغاء المتابعة" : "متابعة")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(OpenlySecondaryButtonStyle())
                    .disabled(relationBusy)

                    Menu {
                        Button(user.viewerHasMuted == true ? "إلغاء الكتم" : "كتم") {
                            Task { await setRelation("mute", enabled: user.viewerHasMuted != true) }
                        }
                        Button(user.viewerHasBlocked == true ? "إلغاء الحظر" : "حظر", role: .destructive) {
                            Task { await setRelation("block", enabled: user.viewerHasBlocked != true) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(OpenlyTheme.muted)
                            .frame(width: 46, height: 44)
                            .background(OpenlyTheme.surfaceSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
                    }
                    .disabled(relationBusy)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .background(OpenlyTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }

    @ViewBuilder
    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("الكتابات")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(OpenlyTheme.ink)
                Spacer()
                if !posts.isEmpty {
                    Text("\(posts.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OpenlyTheme.subtle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if posts.isEmpty {
                EmptyState(icon: "text.bubble", title: "لا توجد منشورات", message: "لا توجد كتابات لهذه الهوية بعد.")
                    .padding(.top, -8)
            } else {
                ForEach(posts) { post in
                    PostCard(post: post)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading || user == nil else { return }
        isLoading = true
        do {
            async let profile = session.api.user(code: code)
            async let feed = session.api.feed(author: code)
            async let commonGround = session.api.publicInterestProfile(code: code)
            async let taste = session.api.publicMusicProfile(code: code)

            let loadedUser = try await profile
            let feedResult = try await feed
            user = loadedUser
            posts = feedResult.items
            interests = (try? await commonGround) ?? nil
            music = (try? await taste) ?? nil
        } catch {
            session.alertMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func setRelation(_ kind: String, enabled: Bool) async {
        guard session.requireLogin(), !relationBusy else { return }
        relationBusy = true
        defer { relationBusy = false }
        do {
            try await session.api.setRelation(code: code, kind: kind, enabled: enabled)
            user = try await session.api.user(code: code)
        } catch {
            session.alertMessage = error.localizedDescription
        }
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
