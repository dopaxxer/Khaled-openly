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
    init() { Task { await refresh() } }
    func refresh() async { do { user = try await api.sessionUser() } catch { user = nil }; isBooting = false }
    func login(email: String, password: String) async throws { try await api.login(email: email, password: password); await refresh() }
    func logout() async { do { try await api.logout() } catch {}; user = nil }
    func requireLogin() -> Bool { guard user != nil else { alertMessage = "سجّل الدخول لإكمال هذه العملية."; return false }; return true }
}

enum OpenlyTheme {
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 109/255, green: 139/255, blue: 1, alpha: 1) : UIColor(red: 22/255, green: 39/255, blue: 122/255, alpha: 1) })
    static let accentStrong = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 139/255, green: 163/255, blue: 1, alpha: 1) : UIColor(red: 42/255, green: 68/255, blue: 184/255, alpha: 1) })
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 5/255, green: 7/255, blue: 15/255, alpha: 1) : UIColor(red: 245/255, green: 245/255, blue: 244/255, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 8/255, green: 11/255, blue: 22/255, alpha: 1) : .white })
    static let surfaceSoft = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 17/255, green: 22/255, blue: 41/255, alpha: 1) : UIColor(red: 238/255, green: 240/255, blue: 247/255, alpha: 1) })
    static let line = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 26/255, green: 32/255, blue: 56/255, alpha: 1) : UIColor(red: 228/255, green: 229/255, blue: 238/255, alpha: 1) })
    static let muted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 152/255, green: 161/255, blue: 189/255, alpha: 1) : UIColor(red: 86/255, green: 95/255, blue: 128/255, alpha: 1) })
    static let subtle = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 109/255, green: 117/255, blue: 149/255, alpha: 1) : UIColor(red: 134/255, green: 142/255, blue: 166/255, alpha: 1) })
    static let foreground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 238/255, green: 241/255, blue: 248/255, alpha: 1) : UIColor(red: 11/255, green: 17/255, blue: 48/255, alpha: 1) })
    static let card = surface
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    var body: some View {
        ZStack {
            OpenlyTheme.background.ignoresSafeArea()
            if session.isBooting {
                VStack(spacing: 14) { BrandLockup(markSize: 38); ProgressView().controlSize(.small); Text("جارِ فتح Openly").font(.footnote).foregroundColor(OpenlyTheme.muted) }
            } else { MainTabView() }
        }
        .alert("Openly", isPresented: Binding(get: { session.alertMessage != nil }, set: { if !$0 { session.alertMessage = nil } }), actions: { Button("حسنًا", role: .cancel) { session.alertMessage = nil } }, message: { Text(session.alertMessage ?? "") })
    }
}

struct MainTabView: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            FeedView().tabItem { Label("الرئيسية", systemImage: "house") }.tag(0)
            SearchView().tabItem { Label("بحث", systemImage: "magnifyingglass") }.tag(1)
            ComposerView(onPublished: { selection = 0 }).tabItem { Label("اكتب", systemImage: "square.and.pencil") }.tag(2)
            AccountView().tabItem { Label("حسابي", systemImage: "person.crop.circle") }.tag(3)
        }
        .toolbarBackground(OpenlyTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 28
    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: markSize)
            Text("Openly").font(.system(size: markSize <= 30 ? 17 : 22, weight: .bold)).tracking(-0.3).foregroundColor(OpenlyTheme.foreground)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore).accessibilityLabel("Openly")
    }
}

struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle().fill(OpenlyTheme.surface).overlay(Circle().stroke(OpenlyTheme.line, lineWidth: 1))
            Text("O").font(.system(size: size * 0.45, weight: .heavy)).foregroundColor(OpenlyTheme.accent)
        }
        .frame(width: size, height: size)
        .shadow(color: OpenlyTheme.accent.opacity(0.12), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

struct ScreenHeader: View {
    let title: String; let subtitle: String?
    init(_ title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(OpenlyTheme.foreground)
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundColor(OpenlyTheme.muted).lineSpacing(3) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 16)
    }
}

struct IdentityBadge: View {
    let code: String; let color: String?
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: color) ?? OpenlyTheme.accent).frame(width: 8, height: 8).overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 0.5))
            Text(code).font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(0.5).foregroundColor(OpenlyTheme.foreground).environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct EmptyState: View {
    let icon: String; let title: String; let message: String
    var body: some View { VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundColor(OpenlyTheme.subtle).padding(.bottom, 6); Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(OpenlyTheme.foreground); Text(message).font(.system(size: 14)).foregroundColor(OpenlyTheme.muted).multilineTextAlignment(.center).lineSpacing(4) }.frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.vertical, 48) }
}

extension Color {
    init?(hex: String?) { guard let hex else { return nil }; let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted); guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }; self.init(red: Double((value >> 16) & 0xFF)/255, green: Double((value >> 8) & 0xFF)/255, blue: Double(value & 0xFF)/255) }
}
