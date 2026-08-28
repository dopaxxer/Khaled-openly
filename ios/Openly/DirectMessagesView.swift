import Foundation
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
    @State private var olderCursor: String?
    @State private var latestCursor: String?
    @State private var hasMore = false
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isLoadingOlder = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var retryNonce: UUID?
    @State private var retryBody: String?
    @State private var shouldScrollToBottom = true
    @State private var presence = DirectPresenceResponse(online: false, typing: false, lastSeenAt: nil)
    @State private var lastTypingSignalAt = Date.distantPast
    @State private var typingSequence = 0
    @FocusState private var composerFocused: Bool

    init(conversation: DirectConversation) {
        _conversation = State(initialValue: conversation)
    }

    var body: some View {
        VStack(spacing: 0) {
            presenceStrip

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
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _ in
                        guard shouldScrollToBottom, let last = messages.last else { return }
                        shouldScrollToBottom = false
                        withAnimation(.easeOut(duration: 0.18)) {
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
            await loadLatest()
            await touchPresence(typing: false)
            await refreshPresence()

            var heartbeatTick = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                } catch {
                    return
                }
                guard scenePhase == .active else { continue }

                await loadIncremental()
                await refreshPresence()

                heartbeatTick += 1
                if heartbeatTick >= 6 {
                    heartbeatTick = 0
                    await touchPresence(typing: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onChange(of: draft) { value in
            signalTyping(for: value)
        }
        .onDisappear {
            Task { await touchPresence(typing: false) }
        }
    }

    private var presenceStrip: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(presence.online ? Color.green : OpenlyTheme.line)
                .frame(width: 7, height: 7)

            Text(presence.typing ? "يكتب…" : (presence.online ? "متصل الآن" : "غير متصل"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(presence.typing ? OpenlyTheme.accent : OpenlyTheme.subtle)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 27)
        .background(OpenlyTheme.surface.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(OpenlyTheme.line).frame(height: 1)
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
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
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
    private func loadLatest() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await session.api.directMessages(
                conversationID: conversation.conversationId,
                limit: 60
            )
            conversation = response.conversation
            shouldScrollToBottom = true
            messages = merge(messages, response.items)
            olderCursor = response.nextCursor
            hasMore = response.hasMore
            latestCursor = cursor(for: messages.last)

            if (response.conversation.unreadCount ?? 0) > 0 {
                _ = try? await session.api.markDirectConversationRead(
                    conversationID: conversation.conversationId
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadIncremental() async {
        guard let latestCursor else { return }

        do {
            let response = try await session.api.directMessages(
                conversationID: conversation.conversationId,
                afterCursor: latestCursor,
                limit: 50
            )
            conversation = response.conversation

            if !response.items.isEmpty {
                shouldScrollToBottom = true
                messages = merge(messages, response.items)
                self.latestCursor = cursor(for: messages.last)
            }

            if (response.conversation.unreadCount ?? 0) > 0 {
                _ = try? await session.api.markDirectConversationRead(
                    conversationID: conversation.conversationId
                )
            }
        } catch {
            // Silent refresh errors should never freeze or replace the thread.
        }
    }

    @MainActor
    private func refreshPresence() async {
        do {
            presence = try await session.api.directMessagePresence(
                conversationID: conversation.conversationId
            )
        } catch {
            // Presence is best-effort and must not affect the conversation.
        }
    }

    @MainActor
    private func touchPresence(typing: Bool) async {
        try? await session.api.touchDirectMessagePresence(
            conversationID: conversation.conversationId,
            typing: typing
        )
    }

    @MainActor
    private func signalTyping(for value: String) {
        typingSequence += 1
        let sequence = typingSequence
        let hasText = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let now = Date()

        if hasText && now.timeIntervalSince(lastTypingSignalAt) >= 1.1 {
            lastTypingSignalAt = now
            Task { await touchPresence(typing: true) }
        } else if !hasText {
            Task { await touchPresence(typing: false) }
        }

        Task {
            do {
                try await Task.sleep(nanoseconds: 2_200_000_000)
            } catch {
                return
            }
            guard sequence == typingSequence else { return }
            await touchPresence(typing: false)
        }
    }

    @MainActor
    private func loadOlder() async {
        guard let olderCursor, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let response = try await session.api.directMessages(
                conversationID: conversation.conversationId,
                cursor: olderCursor,
                limit: 60
            )
            shouldScrollToBottom = false
            messages = merge(messages, response.items)
            self.olderCursor = response.nextCursor
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
            shouldScrollToBottom = true
            messages = merge(messages, [message])
            latestCursor = cursor(for: messages.last)
            draft = ""
            retryBody = nil
            retryNonce = nil
            composerFocused = true
            await touchPresence(typing: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cursor(for message: DirectMessage?) -> String? {
        guard let message else { return nil }
        return "\(message.createdAt)|\(message.id)"
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
    }
}

private enum DirectMessageTime {
    static func label(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, let date = OpenlyDate.date(from: raw) else { return nil }

        let output = DateFormatter()
        output.locale = Locale.current
        output.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        output.timeStyle = .short
        return output.string(from: date)
    }
}
