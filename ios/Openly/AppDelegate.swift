import SwiftUI
import GoogleSignIn

@main
struct OpenlyApp: App {
    @StateObject private var session = AppSession()
    @AppStorage("openly.appearance") private var appearanceRaw = OpenlyAppearance.system.rawValue
    @AppStorage("openly.language") private var languageRaw = OpenlyLanguage.arabic.rawValue
    @AppStorage("openly.colorTheme") private var colorThemeRaw = OpenlyColorTheme.ultramarine.rawValue

    private var selectedAppearance: OpenlyAppearance {
        OpenlyAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var selectedLanguage: OpenlyLanguage {
        OpenlyLanguage(rawValue: languageRaw) ?? .arabic
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environment(\.locale, selectedLanguage.locale)
                .environment(\.layoutDirection, selectedLanguage.layoutDirection)
                .tint((OpenlyColorTheme(rawValue: colorThemeRaw) ?? .crimson).accent)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

enum OpenlyLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arabic: return "العربية"
        case .english: return "English"
        }
    }

    var subtitle: String {
        switch self {
        case .arabic: return "واجهة عربية من اليمين إلى اليسار"
        case .english: return "English interface, left to right"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
    var layoutDirection: LayoutDirection { self == .arabic ? .rightToLeft : .leftToRight }
}

enum OpenlyColorTheme: String, CaseIterable, Identifiable {
    case ultramarine
    case crimson
    case forest
    case amber
    case violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultramarine: return "أزرق ملكي"
        case .crimson: return "عنّابي"
        case .forest: return "غابي"
        case .amber: return "كهرماني"
        case .violet: return "بنفسجي"
        }
    }

    var swatch: Color {
        switch self {
        case .ultramarine: return Color(red: 22/255, green: 39/255, blue: 122/255)
        case .crimson: return Color(red: 184/255, green: 36/255, blue: 76/255)
        case .forest: return Color(red: 31/255, green: 122/255, blue: 66/255)
        case .amber: return Color(red: 179/255, green: 118/255, blue: 15/255)
        case .violet: return Color(red: 124/255, green: 58/255, blue: 237/255)
        }
    }

    var accent: Color {
        switch self {
        case .ultramarine:
            return adaptiveColor(light: (22, 39, 122), dark: (142, 160, 255))
        case .crimson:
            return adaptiveColor(light: (122, 22, 48), dark: (255, 107, 133))
        case .forest:
            return adaptiveColor(light: (20, 83, 45), dark: (95, 211, 147))
        case .amber:
            return adaptiveColor(light: (107, 61, 8), dark: (255, 184, 77))
        case .violet:
            return adaptiveColor(light: (76, 29, 149), dark: (183, 148, 246))
        }
    }

    var accentStrong: Color {
        switch self {
        case .ultramarine:
            return adaptiveColor(light: (22, 39, 122), dark: (166, 179, 255))
        case .crimson:
            return adaptiveColor(light: (184, 36, 76), dark: (255, 143, 163))
        case .forest:
            return adaptiveColor(light: (31, 122, 66), dark: (127, 224, 168))
        case .amber:
            return adaptiveColor(light: (138, 82, 16), dark: (255, 201, 120))
        case .violet:
            return adaptiveColor(light: (124, 58, 237), dark: (201, 167, 250))
        }
    }

    var accentSoft: Color {
        switch self {
        case .ultramarine:
            return adaptiveColor(light: (235, 238, 250), dark: (35, 39, 61))
        case .crimson:
            return adaptiveColor(light: (249, 235, 239), dark: (62, 29, 39))
        case .forest:
            return adaptiveColor(light: (234, 244, 237), dark: (25, 54, 39))
        case .amber:
            return adaptiveColor(light: (249, 241, 226), dark: (58, 43, 24))
        case .violet:
            return adaptiveColor(light: (242, 236, 252), dark: (48, 36, 70))
        }
    }
}

enum OpenlyAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "حسب الجهاز"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "يتبع مظهر الآيفون"
        case .light: return "واجهة Openly الفاتحة"
        case .dark: return "واجهة Openly الليلية"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published var user: UserSummary?
    @Published var isBooting = true
    @Published var alertMessage: String?
    @Published var needsInterestOnboarding = false
    @Published private(set) var feedRevision = 0
    let api = APIClient.shared

    private static let cachedUserKey = "openly.cachedUser"
    private static let interestOnboardingKeyPrefix = "openly.interestOnboarding."

    init() {
        if let cached = Self.loadCachedUser() {
            user = cached
            // A real native app should not block its whole UI on a network
            // round trip every time it returns to the foreground.
            isBooting = false
        }

        NotificationCenter.default.addObserver(
            forName: .openlySessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.clearUser() }
        }
        Task { await refresh() }
    }

    func refresh(afterAuthentication: Bool = false) async {
        do {
            let refreshed = try await api.sessionUser()
            user = refreshed
            if let refreshed {
                Self.cacheUser(refreshed)
                if afterAuthentication {
                    await evaluateInterestOnboarding(for: refreshed)
                }
            } else {
                Self.removeCachedUser()
                needsInterestOnboarding = false
            }
        } catch {
            // Do not turn a timeout or temporary server failure into a logout.
            // A real 401 already emits .openlySessionExpired from APIClient,
            // which clears the user and cache through the observer above.
        }
        isBooting = false
    }

    func updateProfile(publicCode: String, identityColor: String, status: String, bio: String) async throws {
        user = try await api.updateProfile(
            publicCode: publicCode,
            identityColor: identityColor,
            status: status,
            bio: bio
        )
        markFeedChanged()
    }

    func requestOTP(method: String, email: String? = nil, phone: String? = nil) async throws -> OTPRequestResponse {
        try await api.requestOTP(method: method, email: email, phone: phone)
    }

    func verifyOTP(method: String, target: String, token: String) async throws {
        try await api.verifyOTP(method: method, target: target, token: token)
        await refresh(afterAuthentication: true)
    }

    func signInWithNativeToken(provider: String, idToken: String, accessToken: String? = nil, nonce: String? = nil) async throws {
        try await api.signInWithNativeToken(provider: provider, idToken: idToken, accessToken: accessToken, nonce: nonce)
        await refresh(afterAuthentication: true)
    }

    // Kept for backwards compatibility with already-issued password accounts.
    func login(email: String, password: String) async throws {
        try await api.login(email: email, password: password)
        await refresh(afterAuthentication: true)
    }

    func logout() async {
        do { try await api.logout() } catch { }
        clearUser()
    }

    private func clearUser() {
        user = nil
        needsInterestOnboarding = false
        Self.removeCachedUser()
    }

    func completeInterestOnboarding() {
        guard let user else {
            needsInterestOnboarding = false
            return
        }
        UserDefaults.standard.set(true, forKey: Self.interestOnboardingKey(for: user.publicCode))
        needsInterestOnboarding = false
    }

    private func evaluateInterestOnboarding(for user: UserSummary) async {
        let key = Self.interestOnboardingKey(for: user.publicCode)
        guard !UserDefaults.standard.bool(forKey: key),
              Self.isRecentlyCreated(user.createdAt) else {
            needsInterestOnboarding = false
            return
        }

        do {
            let profile = try await api.interestProfile()
            needsInterestOnboarding = profile.items.isEmpty
            if !profile.items.isEmpty {
                UserDefaults.standard.set(true, forKey: key)
            }
        } catch {
            // Auth succeeded; a temporary interest API failure must not trap the
            // user on onboarding or prevent the main application from opening.
            needsInterestOnboarding = false
        }
    }

    private static func interestOnboardingKey(for publicCode: String) -> String {
        interestOnboardingKeyPrefix + publicCode.uppercased()
    }

    private static func isRecentlyCreated(_ raw: String?) -> Bool {
        guard let raw else { return false }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        guard let created = fractional.date(from: raw) ?? standard.date(from: raw) else {
            return false
        }

        let age = Date().timeIntervalSince(created)
        return age >= -300 && age <= 24 * 60 * 60
    }

    private static func loadCachedUser() -> UserSummary? {
        guard let data = UserDefaults.standard.data(forKey: cachedUserKey) else { return nil }
        return try? JSONDecoder().decode(UserSummary.self, from: data)
    }

    private static func cacheUser(_ user: UserSummary) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: cachedUserKey)
    }

    private static func removeCachedUser() {
        UserDefaults.standard.removeObject(forKey: cachedUserKey)
    }

    func markFeedChanged() {
        feedRevision &+= 1
    }

    func requireLogin() -> Bool {
        guard user != nil else {
            alertMessage = "سجّل الدخول لإكمال هذه العملية."
            return false
        }
        return true
    }
}

private func adaptiveColor(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
    Color(uiColor: UIColor { traits in
        let value = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat(value.0) / 255,
            green: CGFloat(value.1) / 255,
            blue: CGFloat(value.2) / 255,
            alpha: 1
        )
    })
}

enum OpenlyTheme {
    // Openly V2: warm paper, dark ink, quiet surfaces. These values mirror
    // the web/Figma direction while keeping the existing dynamic theme system.
    static let background = adaptiveColor(light: (247, 244, 238), dark: (17, 17, 19))
    static let surface = adaptiveColor(light: (255, 253, 248), dark: (25, 25, 28))
    static let surfaceSoft = adaptiveColor(light: (244, 239, 231), dark: (31, 31, 34))
    static let elevated = adaptiveColor(light: (252, 249, 243), dark: (34, 34, 38))
    static let line = adaptiveColor(light: (233, 225, 216), dark: (44, 44, 49))
    static let lineStrong = adaptiveColor(light: (217, 206, 194), dark: (63, 63, 69))
    static let ink = adaptiveColor(light: (23, 21, 19), dark: (232, 230, 226))
    static let muted = adaptiveColor(light: (107, 98, 91), dark: (154, 152, 148))
    static let subtle = adaptiveColor(light: (149, 138, 130), dark: (112, 110, 106))

    private static var selectedColorTheme: OpenlyColorTheme {
        let raw = UserDefaults.standard.string(forKey: "openly.colorTheme")
        return OpenlyColorTheme(rawValue: raw ?? "") ?? .crimson
    }

    static var accent: Color { selectedColorTheme.accent }
    static var accentStrong: Color { selectedColorTheme.accentStrong }
    static var accentSoft: Color { selectedColorTheme.accentSoft }
    static let accentForeground = adaptiveColor(light: (255, 250, 244), dark: (25, 25, 28))
    static let danger = adaptiveColor(light: (180, 35, 24), dark: (248, 113, 113))
    static var card: Color { surfaceSoft }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            OpenlyTheme.background.ignoresSafeArea()
            if session.isBooting {
                VStack(spacing: 16) {
                    BrandLockup(markSize: 44)
                    ProgressView()
                        .tint(OpenlyTheme.accent)
                    Text("جارِ فتح Openly")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(OpenlyTheme.muted)
                }
            } else if session.user == nil {
                NavigationView { LoginView() }
                    .navigationViewStyle(.stack)
            } else if session.needsInterestOnboarding {
                NavigationView {
                    InterestPreferencesView(
                        isOnboarding: true,
                        onComplete: { session.completeInterestOnboarding() }
                    )
                }
                .navigationViewStyle(.stack)
            } else {
                MainTabView()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, !session.isBooting else { return }
            Task { await session.refresh() }
        }
        .alert(
            "Openly",
            isPresented: Binding(
                get: { session.alertMessage != nil },
                set: { if !$0 { session.alertMessage = nil } }
            ),
            actions: { Button("حسنًا", role: .cancel) { session.alertMessage = nil } },
            message: { Text(session.alertMessage ?? "") }
        )
    }
}

struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("Home", systemImage: selection == 0 ? "house.fill" : "house") }
                .tag(0)

            InterestDiscoveryView()
                .tabItem { Label("Explore", systemImage: selection == 1 ? "safari.fill" : "safari") }
                .tag(1)

            NativeWriteView()
                .tabItem { Label("Write", systemImage: selection == 2 ? "square.and.pencil.circle.fill" : "square.and.pencil") }
                .tag(2)

            AccountView()
                .tabItem { Label("You", systemImage: selection == 3 ? "person.crop.circle.fill" : "person.crop.circle") }
                .tag(3)
        }
        .tint(OpenlyTheme.accent)
        .toolbarBackground(OpenlyTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct AppHeader: View {
    @EnvironmentObject private var session: AppSession
    @State private var unreadCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                BrandLockup(markSize: 34)
                Text("Public space · chronological")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(OpenlyTheme.muted)
                    .environment(\.layoutDirection, .leftToRight)
            }

            Spacer(minLength: 12)

            NavigationLink(destination: NotificationsView()) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(OpenlyTheme.ink)
                        .frame(width: 38, height: 38)

                    if unreadCount > 0 {
                        Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(OpenlyTheme.accent)
                            .clipShape(Capsule())
                            .offset(x: 3, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)

            if let user = session.user {
                NavigationLink(destination: AccountView()) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(hex: user.identityColor) ?? OpenlyTheme.accent)
                            .frame(width: 9, height: 9)
                        Text(user.publicCode)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(OpenlyTheme.surface)
                    .overlay(Capsule().stroke(OpenlyTheme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(OpenlyTheme.background)
        .task(id: session.user?.publicCode) {
            if session.user != nil, let count = try? await session.api.unreadNotificationCount() {
                unreadCount = count
            } else {
                unreadCount = 0
            }
        }
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 32

    var body: some View {
        Text("openly")
            .font(.system(size: markSize <= 34 ? 27 : 30, weight: .bold))
            .tracking(-0.8)
            .foregroundColor(OpenlyTheme.ink)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel("Openly")
    }
}

struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().stroke(OpenlyTheme.muted.opacity(0.7), lineWidth: 1)
            Image(systemName: "water.waves")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundColor(Color(red: 31 / 255, green: 57 / 255, blue: 126 / 255))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct IdentityAvatar: View {
    let code: String
    let color: String?
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color(hex: color) ?? OpenlyTheme.accent)
            .frame(width: size, height: size)
            .overlay(
                Text(String(code.prefix(2)).uppercased())
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundColor(.white)
                    .environment(\.layoutDirection, .leftToRight)
            )
            .accessibilityHidden(true)
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(OpenlyTheme.ink)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }
}

struct IdentityBadge: View {
    let code: String
    let color: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: color) ?? OpenlyTheme.accent)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
            Text(code)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(OpenlyTheme.ink)
                .environment(\.layoutDirection, .leftToRight)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(OpenlyTheme.muted)
            }
            Text(LocalizedStringKey(title))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
            Text(LocalizedStringKey(message))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 56)
    }
}

struct OpenlyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(OpenlyTheme.accentForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(OpenlyTheme.accent)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct OpenlyFieldContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(OpenlyTheme.background)
            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1.2))
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
