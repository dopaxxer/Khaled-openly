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

    func requireLogin() -> Bool {
        guard user != nil else {
            alertMessage = "سجّل الدخول لإكمال هذه العملية."
            return false
        }
        return true
    }
}

// Mirrors the web app's paper-and-ink palette (app/globals.css) value for
// value, so the two clients read as the same product. A text-first surface
// lives or dies on how type sits on it: the ground is warm paper rather than
// screen white, and dark is a warm near-black rather than #000 — pure black
// under pure white haloes badly over a long column of Arabic type.
//
// Accent is the ink colour itself, not a hue. Colour here is reserved for
// feedback and for each person's own identity dot, so nothing competes with
// the writing.
private func dynamicColor(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
    Color(uiColor: UIColor { traits in
        let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    })
}

enum OpenlyTheme {
    /// --accent: the ink itself in light, the off-white ink in dark.
    static let accent = dynamicColor(light: (22, 23, 26), dark: (232, 230, 226))
    /// --accent-foreground: what sits *on* the accent. Inverts with it, so a
    /// spinner or label on a filled button stays legible in both schemes.
    static let accentForeground = dynamicColor(light: (251, 250, 247), dark: (25, 25, 28))
    /// --background
    static let background = dynamicColor(light: (243, 241, 236), dark: (17, 17, 19))
    /// --surface: the reading column, a step above its surround.
    static let surface = dynamicColor(light: (251, 250, 247), dark: (25, 25, 28))
    /// --surface-soft
    static let surfaceSoft = dynamicColor(light: (240, 238, 233), dark: (33, 33, 36))
    /// --line
    static let line = dynamicColor(light: (231, 228, 221), dark: (44, 44, 49))
    /// --line-strong
    static let lineStrong = dynamicColor(light: (216, 212, 202), dark: (63, 63, 69))
    /// --foreground
    static let ink = dynamicColor(light: (22, 23, 26), dark: (232, 230, 226))
    /// --muted
    static let muted = dynamicColor(light: (92, 95, 102), dark: (154, 152, 148))
    /// --subtle
    static let subtle = dynamicColor(light: (138, 141, 148), dark: (112, 110, 106))
    /// --danger
    static let danger = dynamicColor(light: (180, 35, 24), dark: (248, 113, 113))
    static let card = surfaceSoft
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            OpenlyTheme.background.ignoresSafeArea()
            Group {
                if session.isBooting {
                    VStack(spacing: 14) {
                        BrandLockup(markSize: 38)
                        ProgressView()
                            .controlSize(.small)
                        Text("جارِ فتح open")
                            .font(.footnote)
                            .foregroundColor(OpenlyTheme.muted)
                    }
                } else {
                    MainTabView()
                }
            }
        }
        .alert(
            "open",
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
                .tabItem { Label("الرئيسية", systemImage: "house") }
                .tag(0)

            SearchView()
                .tabItem { Label("بحث", systemImage: "magnifyingglass") }
                .tag(1)

            ComposerView(onPublished: { selection = 0 })
                .tabItem { Label("اكتب", systemImage: "square.and.pencil") }
                .tag(2)

            AccountView()
                .tabItem { Label("حسابي", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .toolbarBackground(OpenlyTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: markSize)
            Text("open")
                .font(.system(size: markSize <= 30 ? 17 : 22, weight: .bold, design: .default))
                .tracking(-0.3)
                .foregroundColor(OpenlyTheme.ink)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("open")
    }
}

/// A disc, matching the web `.brand-mark` — the mark is round there, not a
/// lettered box.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(OpenlyTheme.surface)
            Circle().stroke(OpenlyTheme.lineStrong, lineWidth: 1)
            Text("O")
                .font(.system(size: size * 0.47, weight: .heavy, design: .default))
                .foregroundColor(OpenlyTheme.ink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Identity is pseudonymous: a colour plus a short code, never a photo. The
/// avatar renders that as a plain colour disc carrying the code's first two
/// characters — the same treatment the web client uses.
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(OpenlyTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

struct IdentityBadge: View {
    let code: String
    let color: String?

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(hex: color) ?? OpenlyTheme.accent)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 0.5))
            Text(code)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
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
