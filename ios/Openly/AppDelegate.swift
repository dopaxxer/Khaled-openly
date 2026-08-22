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
    static let accent = Color(red: 22 / 255, green: 39 / 255, blue: 122 / 255)
    static let softAccent = accent.opacity(0.10)
    static let card = Color(uiColor: .secondarySystemBackground)
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            if session.isBooting {
                VStack(spacing: 14) {
                    BrandMark(size: 58)
                    ProgressView()
                    Text("جارِ فتح Openly")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                .tabItem { Label("الرئيسية", systemImage: "house") }
                .tag(0)

            SearchView()
                .tabItem { Label("بحث", systemImage: "magnifyingglass") }
                .tag(1)

            ComposerView(onPublished: { selection = 0 })
                .tabItem { Label("اكتب", systemImage: "square.and.pencil") }
                .tag(2)

            NotificationsView()
                .tabItem { Label("الإشعارات", systemImage: "bell") }
                .tag(3)

            AccountView()
                .tabItem { Label("حسابي", systemImage: "person.crop.circle") }
                .tag(4)
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(OpenlyTheme.accent)
            Text("O")
                .font(.system(size: size * 0.58, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Openly")
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
                .font(.system(.title2, design: .rounded).weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct IdentityBadge: View {
    let code: String
    let color: String?

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(hex: color) ?? OpenlyTheme.accent)
                .frame(width: 11, height: 11)
            Text(code)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
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
