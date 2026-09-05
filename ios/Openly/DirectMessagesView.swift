import Foundation
import SwiftUI

struct DirectMessagesView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var conversations: [DirectConversation] = []
    @State private var query = ""
    @State private var hasMore = false
    @State private var loadingMore = false
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
                        ForEach(conversations.filter { query.isEmpty || $0.publicCode.localizedCaseInsensitiveContains(query) || ($0.lastMessageBody?.localizedCaseInsensitiveContains(query) ?? false) }) { conversation in
                            NavigationLink(destination: DirectMessageThreadView(conversation: conversation)) {
                                DirectConversationRow(conversation: conversation)
                            }
                            .buttonStyle(.plain)
                        }
                        if hasMore {
                            Button("عرض المزيد") { Task { await loadMore() } }
                                .buttonStyle(OpenlySecondaryButtonStyle()).disabled(loadingMore)
                                .padding(12)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await load() }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الرسائل")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "message_search")
        .openlyKeyboardDismissal()
        .task {
            if session.user != nil { await load() }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                guard scenePhase == .active, session.user != nil else { continue }
                await load(refresh: true)
            }
        }
    }

    @MainActor
    private func load(refresh: Bool = false) async {
        guard !isLoading || conversations.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.api.directConversations()
            if refresh && conversations.count > response.items.count {
                let ids = Set(response.items.map(\.id))
                conversations = response.items + conversations.filter { !ids.contains($0.id) }
            } else {
                conversations = response.items
                hasMore = response.hasMore
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    @MainActor
    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let response = try await session.api.directConversations(offset: conversations.count)
            let ids = Set(conversations.map(\.id))
            conversations += response.items.filter { !ids.contains($0.id) }
            hasMore = response.hasMore
        } catch { errorMessage = error.localizedDescription }
    }

}

private struct DirectConversationRow: View {
    let conversation: DirectConversation

    var body: some View {
        HStack(spacing: 12) {
            IdentityAvatar(code: conversation.publicCode, color: conversation.identityColor, size: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(conversation.publicCode)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(OpenlyTheme.ink)
                        .environment(\.layoutDirection, .leftToRight)
                    Spacer()
                    if let date = DirectMessageTime.label(conversation.lastMessageAt) {
                        Text(date)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(OpenlyTheme.subtle)
                    }
                }

                if let body = conversation.lastMessageBody, !body.isEmpty {
                    Text(verbatim: (conversation.lastMessageIsMine == true ? OpenlyLocale.string("أنت:") + " " : "") + body)
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

            Image(systemName: "chevron.forward")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    // Keep failed/in-flight messages when navigating away and back this session.
    private var pending: [PendingDirectMessage] {
        get { session.pendingMessages[conversation.conversationId] ?? [] }
        nonmutating set { session.pendingMessages[conversation.conversationId] = newValue }
    }
    @State private var followsLatest = true
    @State private var scrollRequest = UUID()
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

                            if messages.isEmpty && pending.isEmpty {
                                EmptyState(
                                    icon: "message",
                                    title: "لا توجد رسائل",
                                    message: "لا توجد رسائل في هذه المحادثة بعد."
                                )
                                .padding(.top, 48)
                            }

                            ForEach(messages) { message in
                                DirectMessageBubble(message: message).id(message.id)
                            }
                            ForEach(pending) { item in
                                PendingMessageBubble(item: item) {
                                    Task { await deliver(item) }
                                }
                            }
                            Color.clear.frame(height: 1).id("thread.bottom")
                                .onAppear { followsLatest = true }
                                .onDisappear { followsLatest = false }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(DragGesture().onChanged { _ in followsLatest = false })
                    .onChange(of: scrollRequest) { _ in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            proxy.scrollTo("thread.bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: messages.count) { _ in
                        guard shouldScrollToBottom else { return }
                        shouldScrollToBottom = false
                        scrollRequest = UUID()
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !followsLatest && !messages.isEmpty {
                            Button { followsLatest = true; scrollRequest = UUID() } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(OpenlyTheme.surface, in: Circle())
                            }
                            .buttonStyle(OpenlyPressStyle())
                            .accessibilityLabel(Text("message_latest"))
                            .padding(12)
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
        .openlyKeyboardDismissal()
        .toolbar(.hidden, for: .tabBar)
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
            composerFocused = false
            OpenlyKeyboard.dismiss()
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
                        .font(.system(size: 15))
                        .accessibilityIdentifier("message.composer")
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
                            .foregroundColor(OpenlyTheme.accentForeground)
                            .frame(width: 44, height: 44)
                            .background(OpenlyTheme.accent, in: Circle())
                    }
                    .buttonStyle(OpenlyPressStyle())
                    .accessibilityLabel(Text("إرسال"))
                    .accessibilityIdentifier("message.send")
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                    .opacity(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            } else {
                Text("لا يمكن إرسال رسائل جديدة في هذه المحادثة.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .frame(maxWidth: .infinity)
            }

            if draft.count > 2000 {
                Text("message_too_long").font(.footnote).foregroundColor(OpenlyTheme.danger)
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
            let page = DirectMessageCollection.mergeFetchedPage(messages, response.items)
            messages = page.items
            olderCursor = response.nextCursor
            hasMore = response.hasMore
            latestCursor = page.cursor

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
        // An empty conversation still needs polling: nil means fetch latest.

        do {
            let response = try await session.api.directMessages(
                conversationID: conversation.conversationId,
                afterCursor: latestCursor,
                limit: 50
            )
            conversation = response.conversation

            if !response.items.isEmpty {
                shouldScrollToBottom = followsLatest
                let page = DirectMessageCollection.mergeFetchedPage(messages, response.items)
                messages = page.items
                self.latestCursor = page.cursor
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
        let item = PendingDirectMessage(body: body)
        pending.append(item)
        // Clear only the submitted text, before the request. New typing is safe.
        draft = ""
        followsLatest = true
        scrollRequest = UUID()
        await deliver(item)
    }

    @MainActor
    private func deliver(_ item: PendingDirectMessage) async {
        guard !isSending, conversation.canMessage else { return }
        isSending = true
        errorMessage = nil
        if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index].failed = false }
        defer { isSending = false }
        do {
            let message = try await session.api.sendDirectMessage(
                conversationID: conversation.conversationId, body: item.body, clientNonce: item.id
            )
            pending.removeAll { $0.id == item.id }
            shouldScrollToBottom = followsLatest
            messages = merge(messages, [message])
            // Keep polling from the last fetched page, even after a newer send.
            await touchPresence(typing: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } catch {
            if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index].failed = true }
            errorMessage = error.localizedDescription
        }
    }

    private func merge(_ current: [DirectMessage], _ incoming: [DirectMessage]) -> [DirectMessage] {
        DirectMessageCollection.merge(current, incoming)
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
                    HStack(spacing: 4) {
                        Text(label)
                        if message.isMine {
                            Image(systemName: message.readAt == nil ? "checkmark" : "checkmark.circle.fill")
                                .accessibilityIdentifier("message.sent")
                                .accessibilityLabel(Text(message.readAt == nil ? "message_sent" : "message_read"))
                        }
                    }
                        .font(.system(size: 10, weight: .medium))
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
        output.locale = OpenlyLocale.locale
        output.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        output.timeStyle = .short
        return output.string(from: date)
    }
}

private struct PendingMessageBubble: View {
    let item: PendingDirectMessage
    let retry: () -> Void
    var body: some View {
        HStack {
            Spacer(minLength: 54)
            VStack(alignment: .trailing, spacing: 6) {
                Text(verbatim: item.body).font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.failed {
                    Button(action: retry) {
                        Label("message_retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium)).frame(minHeight: 44)
                    }
                    .foregroundColor(OpenlyTheme.danger)
                } else {
                    Label("message_sending", systemImage: "clock").font(.system(size: 11))
                        .foregroundColor(OpenlyTheme.muted)
                }
            }
            .padding(12)
            .background(OpenlyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
