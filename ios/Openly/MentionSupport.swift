import SwiftUI
import UIKit

/// The mention grammar, identical to `private.parse_mention_codes` in the
/// Supabase migration and to `lib/mentions.js` on the web:
///
///     (^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])
///
/// The leading boundary is consumed and the trailing one is a lookahead, which
/// is what lets "@AAAA @BBBB" match twice in every engine. Parsing here only
/// drives highlighting and the composer menu — the server re-parses the stored
/// body and decides which mentions actually exist.
enum MentionParser {
    static let pattern = "(^|[^A-Za-z0-9_@])@([A-Za-z0-9]{4,8})(?![A-Za-z0-9_])"
    static let maxPerItem = 10

    private static let regex = try? NSRegularExpression(pattern: pattern)
    private static let codeRegex = try? NSRegularExpression(pattern: "^[A-HJ-NP-Z2-9]{4,8}$")

    static func isPublicCode(_ value: String) -> Bool {
        guard let codeRegex else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return codeRegex.firstMatch(in: value, range: range) != nil
    }

    /// Distinct, well-formed codes in first-appearance order.
    static func codes(in body: String, limit: Int = maxPerItem) -> [String] {
        guard let regex, limit > 0 else { return [] }
        var found: [String] = []
        let range = NSRange(body.startIndex..., in: body)

        for match in regex.matches(in: body, range: range) {
            guard let codeRange = Range(match.range(at: 2), in: body) else { continue }
            let code = String(body[codeRange]).uppercased()
            guard isPublicCode(code), !found.contains(code) else { continue }
            found.append(code)
            if found.count >= limit { break }
        }
        return found
    }

    enum Segment: Equatable {
        case text(String)
        case mention(display: String, code: String)
    }

    /// Splits `body` for rendering. Only codes in `resolved` become mentions,
    /// so a typo, a deleted account or a block leaves the text as written.
    static func segments(in body: String, resolved: Set<String>) -> [Segment] {
        guard let regex, !resolved.isEmpty, !body.isEmpty else {
            return body.isEmpty ? [] : [.text(body)]
        }

        var segments: [Segment] = []
        var cursor = body.startIndex
        let range = NSRange(body.startIndex..., in: body)

        for match in regex.matches(in: body, range: range) {
            guard
                let fullRange = Range(match.range(at: 0), in: body),
                let boundaryRange = Range(match.range(at: 1), in: body),
                let codeRange = Range(match.range(at: 2), in: body)
            else { continue }

            let rawCode = String(body[codeRange])
            let code = rawCode.uppercased()
            guard resolved.contains(code) else { continue }

            let mentionStart = boundaryRange.upperBound
            if mentionStart > cursor {
                segments.append(.text(String(body[cursor..<mentionStart])))
            }
            segments.append(.mention(display: "@\(rawCode)", code: code))
            cursor = fullRange.upperBound
        }

        if cursor < body.endIndex {
            segments.append(.text(String(body[cursor...])))
        }
        return segments.isEmpty ? [.text(body)] : segments
    }

    /// The token being typed at `caret`, or nil when the caret is not in one.
    struct ActiveQuery: Equatable {
        let query: String
        let range: NSRange
    }

    static func activeQuery(in text: String, caret: Int) -> ActiveQuery? {
        // Works in UTF-16 units because the returned range is handed to
        // NSMutableString, which indexes the same way.
        let units = Array(text.utf16)
        let position = max(0, min(caret, units.count))

        var index = position
        while index > 0 {
            let unit = units[index - 1]
            if unit == asciiAt {
                // The character before "@" has to be a boundary.
                if index - 1 > 0 {
                    let previous = units[index - 2]
                    if isCodeUnit(previous) || previous == asciiUnderscore || previous == asciiAt {
                        return nil
                    }
                }

                let length = position - index
                guard length <= 8 else { return nil }

                // Typing past the token means it is no longer being composed.
                if position < units.count {
                    let next = units[position]
                    if isCodeUnit(next) || next == asciiUnderscore { return nil }
                }

                let query = String(decoding: units[index..<position], as: UTF16.self).uppercased()
                return ActiveQuery(query: query, range: NSRange(location: index - 1, length: length + 1))
            }
            guard isCodeUnit(unit) else { return nil }
            if position - index >= 8 { return nil }
            index -= 1
        }
        return nil
    }

    private static let asciiAt: UInt16 = 64
    private static let asciiUnderscore: UInt16 = 95

    private static func isCodeUnit(_ unit: UInt16) -> Bool {
        (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || (unit >= 48 && unit <= 57)
    }

    // Mentions are rendered as links with a private scheme so a tap can be
    // intercepted and turned into a push instead of leaving the app. Keeping
    // both directions here makes the navigation contract testable.
    static let mentionScheme = "openly-mention"

    static func mentionURL(for code: String) -> URL? {
        let normalized = code.uppercased()
        guard isPublicCode(normalized) else { return nil }
        return URL(string: "\(mentionScheme)://\(normalized)")
    }

    /// The profile code a tapped mention link points at, or nil if the URL is
    /// not one of ours.
    static func profileCode(fromMentionURL url: URL) -> String? {
        guard url.scheme == mentionScheme, let host = url.host else { return nil }
        let normalized = host.uppercased()
        return isPublicCode(normalized) ? normalized : nil
    }

    /// Replaces the token being typed with the canonical `@CODE ` form and
    /// reports where the caret should land.
    static func applyCompletion(to text: String, range: NSRange, code: String) -> (text: String, caret: Int) {
        let canonical = "@\(code.uppercased()) "
        let mutable = NSMutableString(string: text)
        guard range.location >= 0, range.location + range.length <= mutable.length else {
            return (text, (text as NSString).length)
        }
        mutable.replaceCharacters(in: range, with: canonical)
        return (mutable as String, range.location + (canonical as NSString).length)
    }
}

/// Renders a post or comment body with tappable mentions.
///
/// Mentions become links with a private scheme; the openURL handler turns a
/// tap into a push of that profile instead of leaving the app. A background
/// `NavigationLink` does the actual navigation so this works anywhere inside
/// the existing `NavigationView` stacks.
struct MentionText: View {
    let body_: String
    let mentions: [MentionRef]
    var font: Font = .system(size: 19, weight: .medium)
    var color: Color = OpenlyTheme.ink

    @State private var target: String?

    init(_ body: String, mentions: [MentionRef]?, font: Font = .system(size: 19, weight: .medium), color: Color = OpenlyTheme.ink) {
        self.body_ = body
        self.mentions = mentions ?? []
        self.font = font
        self.color = color
    }

    private var resolved: Set<String> {
        Set(mentions.map { $0.publicCode.uppercased() })
    }

    private var attributed: AttributedString {
        var output = AttributedString()
        for segment in MentionParser.segments(in: body_, resolved: resolved) {
            switch segment {
            case .text(let value):
                var run = AttributedString(value)
                run.foregroundColor = color
                output.append(run)
            case .mention(let display, let code):
                var run = AttributedString(display)
                run.foregroundColor = OpenlyTheme.accent
                run.font = font.weight(.bold)
                run.link = MentionParser.mentionURL(for: code)
                output.append(run)
            }
        }
        return output
    }

    var body: some View {
        ZStack {
            NavigationLink(
                destination: Group {
                    if let target { UserProfileView(code: target) }
                },
                isActive: Binding(
                    get: { target != nil },
                    set: { if !$0 { target = nil } }
                ),
                label: { EmptyView() }
            )
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            Text(attributed)
                .font(font)
                .lineSpacing(7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    guard let code = MentionParser.profileCode(fromMentionURL: url) else {
                        return .systemAction
                    }
                    target = code
                    return .handled
                })
        }
    }
}

/// A `UITextView` wrapper, used instead of `TextEditor` because the composer
/// needs the caret position to know which mention is being typed — SwiftUI does
/// not expose the selection on iOS 16.
struct MentionTextEditor: UIViewRepresentable {
    @Binding var text: String
    /// Set by the composer when it rewrites the text itself, so the caret can
    /// be placed after the inserted code. Cleared once applied — without it
    /// the caret would fall back to wherever it was before the rewrite, which
    /// is the wrong place in a now-longer string.
    @Binding var caret: Int?
    var placeholder: String
    var maxLength: Int
    var autoFocus: Bool = false
    var onQueryChange: (MentionParser.ActiveQuery?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 19)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        // Matches the RTL-first layout without forcing direction on Latin text.
        view.textAlignment = .natural
        view.keyboardDismissMode = .interactive
        view.adjustsFontForContentSizeCategory = true

        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = .systemFont(ofSize: 19)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14)
        ])
        context.coordinator.placeholderLabel = placeholderLabel

        if autoFocus {
            // Asking on the next runloop pass is what makes the keyboard open
            // reliably when the view appears inside a freshly pushed screen.
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let limit = (text as NSString).length

        if view.text != text {
            let selected = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selected.location, limit), length: 0)
        }

        if let requested = caret {
            view.selectedRange = NSRange(location: min(max(0, requested), limit), length: 0)
            // Clearing during the update pass would re-enter SwiftUI, so hand
            // it back on the next runloop turn.
            DispatchQueue.main.async { caret = nil }
        }
        view.textColor = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        context.coordinator.placeholderLabel?.text = placeholder
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: MentionTextEditor
        var placeholderLabel: UILabel?

        init(_ parent: MentionTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            if (textView.text as NSString).length > parent.maxLength {
                textView.text = String(textView.text.prefix(parent.maxLength))
            }
            parent.text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
            emitQuery(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            emitQuery(textView)
        }

        private func emitQuery(_ textView: UITextView) {
            let caret = textView.selectedRange.location
            parent.onQueryChange(MentionParser.activeQuery(in: textView.text, caret: caret))
        }
    }
}

/// Debounced mention suggestions for the composer.
@MainActor
final class MentionSuggestionModel: ObservableObject {
    @Published private(set) var items: [MentionRef] = []
    @Published var activeQuery: MentionParser.ActiveQuery?

    private var task: Task<Void, Never>?

    func update(_ query: MentionParser.ActiveQuery?) {
        activeQuery = query
        task?.cancel()

        guard let query, !query.query.isEmpty else {
            items = []
            return
        }

        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            let results = (try? await APIClient.shared.mentionSuggestions(query: query.query)) ?? []
            guard !Task.isCancelled else { return }
            // A slower earlier request must not replace a newer result.
            guard self?.activeQuery == query else { return }
            self?.items = results
        }
    }

    func clear() {
        task?.cancel()
        items = []
        activeQuery = nil
    }
}

/// The suggestion strip shown under a composer.
struct MentionSuggestionBar: View {
    let items: [MentionRef]
    let onSelect: (MentionRef) -> Void

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Color(hex: item.identityColor) ?? OpenlyTheme.accent)
                                    .frame(width: 9, height: 9)
                                Text(item.publicCode)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(OpenlyTheme.surfaceSoft)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(OpenlyTheme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("إشارة إلى \(item.publicCode)")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .background(OpenlyTheme.background)
        }
    }
}
