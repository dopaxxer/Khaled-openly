import SwiftUI
import UIKit

@main
struct OpenlyApp: App {
    @StateObject private var session = AppSession()
    @AppStorage("openly.appearance") private var appearance = "system"

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(preferredScheme)
                .tint(OpenlyTheme.accent)
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published var user: UserSummary?
    @Published var isBooting = true
    @Published var alertMessage: String?
    let api = APIClient.shared

    init() { Task { await refresh() } }

    func refresh() async {
        do { user = try await api.sessionUser() }
        catch { user = nil }
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
    static let orbPaper = dynamic(light: 0xFFFFFF, dark: 0x070A14)
    static let card = surface

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: Int) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

struct CosmicBackground: View {
    var body: some View {
        ZStack {
            OpenlyTheme.background
            RadialGradient(
                colors: [OpenlyTheme.accentStrong.opacity(0.12), .clear],
                center: UnitPoint(x: 0.50, y: -0.12),
                startRadius: 10,
                endRadius: 520
            )
            RadialGradient(
                colors: [OpenlyTheme.accent.opacity(0.07), .clear],
                center: UnitPoint(x: 0.08, y: 0.03),
                startRadius: 5,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            CosmicBackground()
            if session.isBooting {
                VStack(spacing: 14) {
                    BrandLockup(markSize: 42)
                    ProgressView().controlSize(.small)
                    Text("جارِ فتح Openly")
                        .font(.system(size: 13))
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
        ZStack {
            switch selection {
            case 1: SearchView()
            case 2: ComposerView(onPublished: { selection = 0 })
            case 3: AccountView()
            default: FeedView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OpenlyBottomBar(selection: $selection)
        }
    }
}

struct OpenlyBottomBar: View {
    @Binding var selection: Int

    private let items: [(String, String)] = [
        ("house", "الرئيسية"),
        ("magnifyingglass", "بحث"),
        ("square.and.pencil", "اكتب"),
        ("person.crop.circle", "حسابي")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = index }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.0)
                            .font(.system(size: 20, weight: selection == index ? .semibold : .regular))
                            .frame(height: 24)
                        Text(item.1)
                            .font(.system(size: 10, weight: selection == index ? .semibold : .medium))
                    }
                    .foregroundColor(selection == index ? OpenlyTheme.accent : OpenlyTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .background(OpenlyTheme.surface.opacity(0.90))
        .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 0.5) }
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: markSize)
            Text("Openly")
                .font(.system(size: markSize <= 34 ? 17 : 22, weight: .bold))
                .tracking(-0.35)
                .foregroundColor(OpenlyTheme.foreground)
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
            Circle().fill(OpenlyTheme.orbPaper)
            ZStack {
                Capsule()
                    .fill(OpenlyTheme.accent.opacity(0.92))
                    .frame(width: size * 0.68, height: size * 0.23)
                    .rotationEffect(.degrees(-9))
                Capsule()
                    .fill(OpenlyTheme.accentStrong.opacity(0.78))
                    .frame(width: size * 0.58, height: size * 0.14)
                    .offset(x: size * 0.03, y: -size * 0.09)
                    .rotationEffect(.degrees(12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(OpenlyTheme.lineStrong.opacity(0.7), lineWidth: 0.7))
        .shadow(color: OpenlyTheme.accent.opacity(0.16), radius: 11, y: 5)
        .accessibilityHidden(true)
    }
}

struct OpenlyMobileHeader<Leading: View>: View {
    @ViewBuilder let leading: () -> Leading

    init(@ViewBuilder leading: @escaping () -> Leading) {
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 10) {
            BrandLockup(markSize: 32)
            Spacer()
            leading()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(.ultraThinMaterial)
        .background(OpenlyTheme.background.opacity(0.88))
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(OpenlyTheme.foreground)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }
}

struct IdentityBadge: View {
    let code: String
    let color: String?
    var large = false

    var body: some View {
        HStack(spacing: large ? 12 : 8) {
            Circle()
                .fill(Color(hex: color) ?? OpenlyTheme.accent)
                .frame(width: large ? 12 : 8, height: large ? 12 : 8)
                .overlay(Circle().stroke(OpenlyTheme.foreground.opacity(0.16), lineWidth: 0.5))
                .shadow(color: (Color(hex: color) ?? OpenlyTheme.accent).opacity(0.55), radius: large ? 6 : 4)
            Text(code)
                .font(.system(size: large ? 16 : 13, weight: .semibold, design: .monospaced))
                .tracking(large ? 0.8 : 0.65)
                .foregroundColor(OpenlyTheme.foreground)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .light))
                    .foregroundColor(OpenlyTheme.subtle)
                    .padding(.bottom, 3)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OpenlyTheme.foreground)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(OpenlyTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 48)
    }
}

struct OpenlyPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(OpenlyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: OpenlyTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OpenlyTheme.radiusLarge, style: .continuous)
                    .stroke(OpenlyTheme.line, lineWidth: 1)
            )
    }
}

struct OpenlyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 17)
            .frame(minHeight: 42)
            .background(OpenlyTheme.accent)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct OpenlySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(OpenlyTheme.foreground)
            .padding(.horizontal, 17)
            .frame(minHeight: 42)
            .background(OpenlyTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct OpenlyDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(OpenlyTheme.danger)
            .padding(.horizontal, 17)
            .frame(minHeight: 42)
            .background(OpenlyTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(OpenlyTheme.danger.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct OpenlyPillField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(OpenlyTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
    }
}

extension View {
    func openlyPillField() -> some View { modifier(OpenlyPillField()) }
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
