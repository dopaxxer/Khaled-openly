import SwiftUI

/// Native application shell that keeps the primary destinations alive instead
/// of rebuilding the interface every time the user changes tabs.
///
/// This deliberately trades a little extra memory for continuity: scroll
/// position, loaded data, local UI state, and each destination's navigation
/// state remain available while the user moves around Openly.
struct PersistentMainTabView: View {
    private enum Tab: Int, CaseIterable {
        case home
        case explore
        case write
        case you

        var title: LocalizedStringKey {
            switch self {
            case .home: return "Home"
            case .explore: return "Explore"
            case .write: return "Write"
            case .you: return "You"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house"
            case .explore: return "safari"
            case .write: return "square.and.pencil"
            case .you: return "person.crop.circle"
            }
        }

        var selectedIcon: String {
            switch self {
            case .home: return "house.fill"
            case .explore: return "safari.fill"
            case .write: return "square.and.pencil"
            case .you: return "person.crop.circle.fill"
            }
        }
    }

    @State private var selection: Tab = .home
    @State private var isComposerPresented = false

    var body: some View {
        ZStack {
            OpenlyTheme.background.ignoresSafeArea()

            // Keep all main destinations mounted. Using opacity rather than an
            // if/switch means SwiftUI does not discard their @State when the
            // user changes tabs.
            FeedView()
                .opacity(selection == .home ? 1 : 0)
                .allowsHitTesting(selection == .home)
                .accessibilityHidden(selection != .home)
                .zIndex(selection == .home ? 1 : 0)

            InterestDiscoveryView()
                .opacity(selection == .explore ? 1 : 0)
                .allowsHitTesting(selection == .explore)
                .accessibilityHidden(selection != .explore)
                .zIndex(selection == .explore ? 1 : 0)

            AccountView()
                .opacity(selection == .you ? 1 : 0)
                .allowsHitTesting(selection == .you)
                .accessibilityHidden(selection != .you)
                .zIndex(selection == .you ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.16), value: selection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            persistentTabBar
        }
        .sheet(isPresented: $isComposerPresented) {
            NativeWriteView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
    }

    private var persistentTabBar: some View {
        HStack(spacing: 4) {
            tabButton(.home)
            tabButton(.explore)
            composeButton
            tabButton(.you)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OpenlyTheme.line.opacity(0.85))
                .frame(height: 0.5)
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            guard selection != tab else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)

                Text(tab.title)
                    .font(.system(size: 10.5, weight: selection == tab ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(selection == tab ? OpenlyTheme.accent : OpenlyTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(PersistentTabButtonStyle())
    }

    private var composeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isComposerPresented = true
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(OpenlyTheme.accent)
                        .frame(width: 34, height: 34)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(OpenlyTheme.accentForeground)
                }

                Text(Tab.write.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(PersistentTabButtonStyle())
        .accessibilityLabel(Text(Tab.write.title))
    }
}

private struct PersistentTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
