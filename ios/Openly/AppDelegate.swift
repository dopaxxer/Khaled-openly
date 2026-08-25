import SwiftUI

@main
struct OpenlyApp: App {
    @StateObject private var session = AppSession()
    @AppStorage("openly.appearance") private var appearanceRaw = OpenlyAppearance.system.rawValue
    @AppStorage("openly.language") private var languageRaw = OpenlyLanguage.arabic.rawValue

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
                .tint(OpenlyTheme.accent)
                .preferredColorScheme(selectedAppearance.colorScheme)
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

enum OpenlyAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "تلقائي"
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
    @Published private(set) var feedRevision = 0
    let api = APIClient.shared

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            user = try await api.sessionUser()
        } catch {
            user = nil
        }
        isBooting = false
    }

    func login(email: String, password: String) async throws {
        try await api.login(email: email, password: password)
        await refresh()
    }

    func logout() async {
        do { try await api.logout() } catch { }
        user = nil
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
    static let background = adaptiveColor(light: (250, 250, 248), dark: (8, 10, 21))
    static let surface = adaptiveColor(light: (255, 255, 255), dark: (8, 10, 21))
    static let surfaceSoft = adaptiveColor(light: (244, 244, 241), dark: (13, 16, 32))
    static let elevated = adaptiveColor(light: (248, 248, 246), dark: (17, 20, 39))
    static let line = adaptiveColor(light: (232, 232, 227), dark: (27, 31, 54))
    static let lineStrong = adaptiveColor(light: (208, 211, 221), dark: (48, 55, 87))
    static let ink = adaptiveColor(light: (22, 23, 26), dark: (244, 245, 250))
    static let muted = adaptiveColor(light: (92, 95, 106), dark: (156, 164, 189))
    static let subtle = adaptiveColor(light: (132, 136, 151), dark: (111, 120, 152))
    static let accent = adaptiveColor(light: (94, 119, 238), dark: (124, 146, 247))
    static let accentSoft = adaptiveColor(light: (132, 151, 238), dark: (67, 81, 137))
    static let accentForeground = adaptiveColor(light: (255, 255, 255), dark: (7, 10, 20))
    static let danger = adaptiveColor(light: (190, 45, 45), dark: (248, 113, 113))
    static let card = surfaceSoft
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

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
            } else {
                MainTabView()
            }
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
                .tabItem { Label("الرئيسية", systemImage: selection == 0 ? "house.fill" : "house") }
                .tag(0)

            SearchView()
                .tabItem { Label("بحث", systemImage: "magnifyingglass") }
                .tag(1)

            ComposerView(onPublished: { selection = 0 })
                .tabItem { Label("اكتب", systemImage: "square.and.pencil") }
                .tag(2)

            MutualMusicView()
                .tabItem { Label("موسيقى", systemImage: "music.note") }
                .tag(3)

            AccountView()
                .tabItem { Label("حسابي", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(OpenlyTheme.accent)
        .toolbarBackground(OpenlyTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct AppHeader: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        HStack(spacing: 12) {
            BrandLockup(markSize: 34)
            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundColor(OpenlyTheme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            if session.user != nil {
                Button {
                    Task { await session.logout() }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(OpenlyTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(destination: LoginView()) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(OpenlyTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 74)
        .background(OpenlyTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OpenlyTheme.line).frame(height: 1)
        }
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: markSize)
            Text("Openly")
                .font(.system(size: markSize <= 34 ? 20 : 24, weight: .bold))
                .tracking(-0.4)
                .foregroundColor(OpenlyTheme.ink)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
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
