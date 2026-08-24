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

enum OpenlyTheme {
    static let accent = Color(red: 47 / 255, green: 111 / 255, blue: 98 / 255)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 17 / 255, green: 18 / 255, blue: 16 / 255, alpha: 1)
            : UIColor(red: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 21 / 255, green: 22 / 255, blue: 20 / 255, alpha: 1)
            : .white
    })
    static let surfaceSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 27 / 255, green: 28 / 255, blue: 25 / 255, alpha: 1)
            : UIColor(red: 244 / 255, green: 244 / 255, blue: 241 / 255, alpha: 1)
    })
    static let line = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 42 / 255, green: 44 / 255, blue: 39 / 255, alpha: 1)
            : UIColor(red: 232 / 255, green: 232 / 255, blue: 227 / 255, alpha: 1)
    })
    static let muted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 167 / 255, green: 170 / 255, blue: 161 / 255, alpha: 1)
            : UIColor(red: 105 / 255, green: 107 / 255, blue: 101 / 255, alpha: 1)
    })
    static let subtle = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 124 / 255, green: 128 / 255, blue: 118 / 255, alpha: 1)
            : UIColor(red: 143 / 255, green: 145 / 255, blue: 137 / 255, alpha: 1)
    })
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
            Text("Openly")
                .font(.system(size: markSize <= 30 ? 17 : 22, weight: .bold, design: .default))
                .tracking(-0.3)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Openly")
    }
}

struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.primary, lineWidth: 1)
            Text("O")
                .font(.system(size: size * 0.47, weight: .heavy, design: .default))
                .foregroundColor(.primary)
        }
        .frame(width: size, height: size)
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
                .foregroundColor(.primary)
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
