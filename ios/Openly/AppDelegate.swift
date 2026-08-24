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
                .preferredColorScheme(.dark)
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
    // Values sampled from the supplied mobile reference screenshots.
    static let background = Color(red: 8 / 255, green: 10 / 255, blue: 21 / 255)
    static let surface = background
    static let surfaceSoft = Color(red: 13 / 255, green: 16 / 255, blue: 32 / 255)
    static let elevated = Color(red: 17 / 255, green: 20 / 255, blue: 39 / 255)
    static let line = Color(red: 27 / 255, green: 31 / 255, blue: 54 / 255)
    static let lineStrong = Color(red: 48 / 255, green: 55 / 255, blue: 87 / 255)
    static let ink = Color(red: 244 / 255, green: 245 / 255, blue: 250 / 255)
    static let muted = Color(red: 156 / 255, green: 164 / 255, blue: 189 / 255)
    static let subtle = Color(red: 111 / 255, green: 120 / 255, blue: 152 / 255)
    static let accent = Color(red: 124 / 255, green: 146 / 255, blue: 247 / 255)
    static let accentSoft = Color(red: 67 / 255, green: 81 / 255, blue: 137 / 255)
    static let accentForeground = Color(red: 7 / 255, green: 10 / 255, blue: 20 / 255)
    static let danger = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
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

            AccountView()
                .tabItem { Label("حسابي", systemImage: "person.crop.circle") }
                .tag(3)
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
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(OpenlyTheme.ink)
            if let subtitle {
                Text(subtitle)
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
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
            Text(message)
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