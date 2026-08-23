import SwiftUI

@main
struct OpenlyApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(OpenlyTheme.accent)
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published var user: UserSummary?
    @Published var isBooting = true
    @Published var alertMessage: String?
    @Published var unreadCount = 0
    let api = APIClient.shared

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            user = try await api.sessionUser()
            if user != nil {
                unreadCount = (try? await api.notifications().unreadCount) ?? 0
            } else {
                unreadCount = 0
            }
        } catch {
            user = nil
            unreadCount = 0
        }
        isBooting = false
    }

    func refreshUnread() async {
        guard user != nil else { unreadCount = 0; return }
        unreadCount = (try? await api.notifications().unreadCount) ?? unreadCount
    }

    func login(email: String, password: String) async throws {
        try await api.login(email: email, password: password)
        await refresh()
    }

    func logout() async {
        do { try await api.logout() } catch { }
        user = nil
        unreadCount = 0
    }

    func requireLogin() -> Bool {
        guard user != nil else {
            alertMessage = "سجّل الدخول لإكمال هذه العملية."
            return false
        }
        return true
    }
}

enum OpenlyTheme {
    static let background = dynamic(light: 0xF5F5F4, dark: 0x05070F)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x080B16)
    static let surfaceSoft = dynamic(light: 0xEEF0F7, dark: 0x111629)
    static let surfaceHover = dynamic(light: 0xF3F4FA, dark: 0x151B31)
    static let foreground = dynamic(light: 0x0B1130, dark: 0xEEF1F8)
    static let muted = dynamic(light: 0x565F80, dark: 0x98A1BD)
    static let subtle = dynamic(light: 0x868EA6, dark: 0x6D7595)
    static let line = dynamic(light: 0xE4E5EE, dark: 0x1A2038)
    static let lineStrong = dynamic(light: 0xD2D5E2, dark: 0x29304C)
    static let accent = dynamic(light: 0x16277A, dark: 0x6D8BFF)
    static let accentStrong = dynamic(light: 0x2A44B8, dark: 0x8BA3FF)
    static let danger = dynamic(light: 0xB42318, dark: 0xFF9D90)
    static let success = dynamic(light: 0x1A6B4C, dark: 0x6FD3A6)
    static let like = Color(red: 212 / 255, green: 72 / 255, blue: 60 / 255)

    static var accentSoft: Color { accentStrong.opacity(0.09) }
    static var glow: Color { accent.opacity(0.16) }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("openly.appearance") private var appearance = "system"

    var body: some View {
        ZStack {
            OpenlyBackground()
            if session.isBooting {
                VStack(spacing: 16) {
                    BrandLockup(markSize: 44)
                    ProgressView().controlSize(.small)
                    Text("جارِ فتح Openly")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(OpenlyTheme.muted)
                }
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
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

struct OpenlyBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            OpenlyTheme.background
            RadialGradient(
                colors: [OpenlyTheme.accentStrong.opacity(colorScheme == .dark ? 0.14 : 0.075), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
            LinearGradient(
                colors: [.clear, OpenlyTheme.accent.opacity(colorScheme == .dark ? 0.055 : 0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

enum OpenlyTab: Int, CaseIterable {
    case home, search, write, account

    var title: String {
        switch self {
        case .home: return "الرئيسية"
        case .search: return "بحث"
        case .write: return "اكتب"
        case .account: return "حسابي"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .write: return "square.and.pencil"
        case .account: return "person.crop.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .write: return "square.and.pencil"
        case .account: return "person.crop.circle.fill"
        }
    }
}

struct MainTabView: View {
    @State private var selection: OpenlyTab = .home

    var body: some View {
        ZStack {
            switch selection {
            case .home: FeedView()
            case .search: SearchView()
            case .write: ComposerView(onPublished: { selection = .home })
            case .account: AccountView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OpenlyTabBar(selection: $selection)
        }
        .animation(.easeOut(duration: 0.2), value: selection)
    }
}

struct OpenlyTabBar: View {
    @Binding var selection: OpenlyTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OpenlyTab.allCases, id: \.rawValue) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                            .symbolRenderingMode(.monochrome)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .bold : .medium))
                    }
                    .foregroundStyle(selection == tab ? OpenlyTheme.accent : OpenlyTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selection == tab ? OpenlyTheme.accentSoft : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: markSize)
            Text("Openly")
                .font(.system(size: markSize <= 34 ? 18 : 23, weight: .bold, design: .default))
                .tracking(-0.45)
                .foregroundStyle(OpenlyTheme.foreground)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Openly")
    }
}

struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("BrandOrb")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(OpenlyTheme.lineStrong.opacity(0.7), lineWidth: 0.6))
            .shadow(color: OpenlyTheme.accent.opacity(0.18), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

struct OpenlyTopBar<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 12)
            BrandLockup(markSize: 32)
            Spacer(minLength: 12)
            trailing
        }
        .frame(height: 58)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
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
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(OpenlyTheme.foreground)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(OpenlyTheme.muted)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }
}

struct IdentityBadge: View {
    let code: String
    let color: String?
    var large = false

    var body: some View {
        HStack(spacing: large ? 10 : 8) {
            Circle()
                .fill(Color(hex: color) ?? OpenlyTheme.accent)
                .frame(width: large ? 12 : 8, height: large ? 12 : 8)
                .shadow(color: (Color(hex: color) ?? OpenlyTheme.accent).opacity(0.35), radius: 5)
            Text(code)
                .font(.system(size: large ? 16 : 13, weight: .semibold, design: .monospaced))
                .tracking(large ? 0.9 : 0.65)
                .foregroundStyle(OpenlyTheme.foreground)
                .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OpenlyTheme.foreground)
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(OpenlyTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .padding(.horizontal, 28)
    }
}

struct OpenlyIconButton: View {
    let systemName: String
    var badge: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(OpenlyTheme.muted)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
            if badge > 0 {
                Text(badge > 9 ? "9+" : "\(badge)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 15, minHeight: 15)
                    .padding(.horizontal, 1)
                    .background(OpenlyTheme.danger)
                    .clipShape(Capsule())
                    .offset(x: 1, y: 1)
            }
        }
    }
}

struct OpenlyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(colors: [OpenlyTheme.accentStrong, OpenlyTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Capsule())
            .shadow(color: OpenlyTheme.accent.opacity(configuration.isPressed ? 0.08 : 0.22), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct OpenlySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OpenlyTheme.foreground)
            .frame(minHeight: 42)
            .padding(.horizontal, 18)
            .background(OpenlyTheme.surface.opacity(configuration.isPressed ? 0.7 : 0))
            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
            .clipShape(Capsule())
    }
}

struct OpenlyCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(OpenlyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
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
