import SwiftUI
import UIKit

enum OpenlyKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct OpenlyKeyboardDismissal: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { OpenlyKeyboard.dismiss() } label: {
                    Label("keyboard_done", systemImage: "keyboard.chevron.compact.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("keyboard.dismiss")
            }
        }
    }
}

extension View {
    func openlyKeyboardDismissal() -> some View { modifier(OpenlyKeyboardDismissal()) }
}
