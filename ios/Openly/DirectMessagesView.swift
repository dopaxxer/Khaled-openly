import SwiftUI

struct DirectMessagesView: View {
    @EnvironmentObject private var session: AppSession
    @State private var conversations: [DirectConversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if session.user == nil {
                LoginRequiredView(message: "سجّل الدخول لرؤية رسائلك.")
            } else if isLoading && conversations.isEmpty {
                ProgressView("جارِ تحميل الرسائل")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
            } else if let errorMessage, conversations.isEmpty {
                VStack(spacing: 14) {
                    EmptyState(
                        icon: "exclamationmark.bubble",
                        title: "تعذر تحميل الرسائل",
                        message: errorMessage
                    )
                    Button("المحاولة مجددًا") { Task { await load() } }
                        .buttonStyle(OpenlySecondaryButtonStyle())
                }
            } else if conversations.isEmpty {
                EmptyState(
                    icon: "message",
                    title: "لا توجد رسائل بعد",
                    message: "ابدأ من صفحة أي هوية واضغط «رسالة خاصة»."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(conversations) { conversation in
                            NavigationLink(destination: DirectMessageThreadView(conversation: conversation)) {
                                DirectConversationRow(conversation: conversation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الرسائل")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if session.user != nil { await load() }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.api.directConversations()
            conversations = response.items
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DirectConversationRow: View {
    let conversation: DirectConversation

    var body: some View {
        HStack(spacing: 12) {
            IdentityBadge(
                code: conversation.publicCode,
                color: conversation.identityColor ?? "#5C7AEA"
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(conversation.publicCode)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(OpenlyTheme.ink)
                        .environment(\.layoutDirection, .leftToRight)
                    Spacer()
                    if let date = DirectMessageTime.label(conversation.lastMessageAt) {
                        Text(date)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(OpenlyTheme.subtle)
                    }
                }

                if let body = conversation.lastMessageBody, !body.isEmpty {
                    Text(verbatim: (conversation.lastMessageIsMine == true ? NSLocalizedString("أنت:", comment: "") + " " : "") + body)
                        .font(.system(size: 13))
                        .foregroundColor(OpenlyTheme.muted)
                        .lineLimit(1)
                } else {
                    Text("لا توجد رسائل في هذه المحادثة بعد.")
                        .font(.system(size: 13))
                        .foregroundColor(OpenlyTheme.subtle)
                }
            }

            if let unread = conversation.unreadCount, unread > 0 {
                Text(unread > 99 ? "99+" : String(unread))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 3)
                    .background(OpenlyTheme.accent)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OpenlyTheme.subtle)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 76)
        .background(OpenlyTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OpenlyTheme.line).frame(height: 1)
        }
    }
}

struct StartDirectMessageView: View {
    @EnvironmentObject private var session: AppSession
    let code: String

    @State private var conversation: DirectConversation?
    @State private var errorMessage: String?
    @State private var isStarting = false

    var body: some View {
        Group {
            if let conversation {
                DirectMessageThreadView(conversation: conversation)
            } else if let errorMessage {
                VStack(spacing: 14) {
                    EmptyState(
                        icon: "message.badge",
                        title: "تعذر بدء المحادثة",
                        message: errorMessage
                    )
                    Button("المحاولة مجددًا") { Task { await start() } }
                        .buttonStyle(OpenlySecondaryButtonStyle())
                }
                .background(OpenlyTheme.background.ignoresSafeArea())
            } else {
                ProgressView("جارِ فتح المحادثة…")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
                    .background(OpenlyTheme.background.ignoresSafeArea())
            }
        }
        .task {
            if conversation == nil && !isStarting { await start() }
        }
    }

    @MainActor
    private func start() async {
        guard session.requireLogin(), !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            conversation = try await session.api.startDirectConversation(code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DirectMessageThreadView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var conversation: DirectConversation
    @State private var messages: [DirectMessage] = []
    @State private var olderBefore: String?
    @State private var hasMore = false
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isLoadingOlder = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var retryNonce: UUID?
    @State private var retryBody: String?
    @FocusState private var composerFocused: Bool

    init(conversation: DirectConversation) {
        _conversation = State(initialValue: conversation)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && messages.isEmpty {
                Spacer()
                ProgressView("جارِ تحميل الرسائل")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if hasMore {
                                Button(isLoadingOlder ? "جارِ التحميل…" : "عرض رسائل أقدم") {
                                    Task { await loadOlder() }
                                }
                                .buttonStyle(OpenlySecondaryButtonStyle())
                                .disabled(isLoadingOlder)
                                .padding(.vertical, 8)
                            }

                            if messages.isEmpty {
                                EmptyState(
                                    icon: "message",
                                    title: "لا توجد رسائل",
                                    message: "لا توجد رسائل في هذه المحادثة بعد."
                                )
                                .padding(.top, 48)
                            }

                            ForEach(messages) { message in
                                DirectMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _ in
                        guard let last = messages.last else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle(conversation.publicCode)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { composer }
        .task(id: conversation.conversationId) {
            await loadLatest(silent: false)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                if scenePhase == .active {
                    await loadLatest(silent: true)
                }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 8) {
            if conversation.canMessage {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("اكتب رسالة خاصة…", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(OpenlyTheme.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(OpenlyTheme.line, lineWidth: 1)
                        )

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(OpenlyPrimaryButtonStyle())
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("لا يمكن إرسال رسائل جديدة في هذه المحادثة.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(OpenlyTheme.line).frame(height: 1)
        }
    }

    @MainActor
    private func loadLatest(silent: Bool) async {
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        defer { if !silent { isLoading = false } }

        do {
            let response = try await session.api.directMessages(
                conversationID: conversation.conversationId,
                limit: 100
            )
            conversation = response.conversation
            messages = merge(messages, response.items)
            if !silent {
                olderBefore = response.nextBefore
                hasMore = response.hasMore
            }
            _ = try? await session.api.markDirectConversationRead(
                conversationID: conversation.conversationId
            )
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func loadOlder() async {
        guard let olderBefore, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let response = try await session.api.directMessages(
                conversationID: conversation.conversationId,
                before: olderBefore,
                limit: 100
            )
            messages = merge(messages, response.items)
            self.olderBefore = response.nextBefore
            hasMore = response.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 2000, conversation.canMessage, !isSending else { return }

        let nonce: UUID
        if retryBody == body, let retryNonce {
            nonce = retryNonce
        } else {
            nonce = UUID()
            retryBody = body
            retryNonce = nonce
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let message = try await session.api.sendDirectMessage(
                conversationID: conversation.conversationId,
                body: body,
                clientNonce: nonce
            )
            messages = merge(messages, [message])
            draft = ""
            retryBody = nil
            retryNonce = nil
            composerFocused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge(_ current: [DirectMessage], _ incoming: [DirectMessage]) -> [DirectMessage] {
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        incoming.forEach { byID[$0.id] = $0 }
        return byID.values.sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt < $1.createdAt
        }
    }
}

private struct DirectMessageBubble: View {
    let message: DirectMessage

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 54) }

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: message.body)
                    .font(.system(size: 15))
                    .foregroundColor(OpenlyTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let label = DirectMessageTime.label(message.createdAt) {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(OpenlyTheme.subtle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(message.isMine ? OpenlyTheme.accent.opacity(0.12) : OpenlyTheme.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(message.isMine ? OpenlyTheme.accent.opacity(0.18) : OpenlyTheme.line, lineWidth: 1)
            )

            if !message.isMine { Spacer(minLength: 54) }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private enum DirectMessageTime {
    static func label(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: raw)
        }
        guard let date else { return nil }

        let output = DateFormatter()
        output.locale = Locale(identifier: OpenlyLocale.currentLanguageCode == "en" ? "en" : "ar")
        output.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        output.timeStyle = .short
        return output.string(from: date)
    }
}
