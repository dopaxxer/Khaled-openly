import AVFoundation
import SwiftUI

@MainActor
final class AudioPreviewPlayer: ObservableObject {
    static let shared = AudioPreviewPlayer()

    @Published private(set) var activeTrackID: String?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    private init() {}

    func toggle(trackID: String, previewURL: String) {
        guard let url = URL(string: previewURL), url.scheme?.lowercased() == "https" else { return }

        if activeTrackID == trackID {
            stop()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            return
        }

        clearEndObserver()
        player?.pause()

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        activeTrackID = trackID
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finish(trackID: trackID)
            }
        }
        nextPlayer.play()
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        player = nil
        activeTrackID = nil
        clearEndObserver()
    }

    private func finish(trackID: String) {
        guard activeTrackID == trackID else { return }
        stop()
    }

    private func clearEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

struct FeedView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var posts: [Post] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var pendingReset = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AppHeader()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        HomeComposerCard {
                            Task { await load(reset: true) }
                        }

                        if posts.isEmpty && isLoading {
                            ForEach(0..<3, id: \.self) { _ in
                                FeedSkeletonRow()
                            }
                        } else if posts.isEmpty {
                            VStack(spacing: 16) {
                                EmptyState(
                                    icon: "text.bubble",
                                    title: errorMessage == nil ? "لا توجد منشورات بعد" : "تعذر تحميل المنشورات",
                                    message: errorMessage ?? "كن أول من يكتب."
                                )
                                if errorMessage != nil {
                                    Button("المحاولة مجددًا") { Task { await load(reset: true) } }
                                        .buttonStyle(OpenlySecondaryButtonStyle())
                                        .padding(.horizontal, 28)
                                }
                            }
                        } else {
                            ForEach(posts) { post in
                                PostCard(post: post)
                                    .onAppear {
                                        if post.id == posts.last?.id, nextCursor != nil {
                                            Task { await load(reset: false) }
                                        }
                                    }
                            }

                            if let errorMessage, !posts.isEmpty {
                                Text(errorMessage)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(OpenlyTheme.danger)
                                    .padding(.vertical, 12)
                            }
                            if isLoading {
                                ProgressView()
                                    .tint(OpenlyTheme.accent)
                                    .padding(.vertical, 24)
                            } else if nextCursor == nil {
                                Text("هذه كل المنشورات المتاحة.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(OpenlyTheme.subtle)
                                    .padding(.vertical, 28)
                            }
                        }
                    }
                }
                .refreshable { await load(reset: true) }
                .background(OpenlyTheme.background)
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                // Keep the feed stable while the user is reading. Background
                // polling used to replace the whole list every 30 seconds,
                // which could cause visible jumps and unnecessary work.
                await load(reset: true)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await load(reset: true) }
            }
            .onChange(of: session.feedRevision) { _ in
                Task { await load(reset: true) }
            }
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func load(reset: Bool) async {
        if isLoading {
            if reset { pendingReset = true }
            return
        }
        isLoading = true
        if reset { errorMessage = nil }
        do {
            let response = try await session.api.feed(cursor: reset ? nil : nextCursor)
            if reset {
                posts = response.items
            } else {
                posts += response.items.filter { item in
                    !posts.contains(where: { $0.id == item.id })
                }
            }
            nextCursor = response.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        if pendingReset {
            pendingReset = false
            await load(reset: true)
        }
    }
}

private struct HomeComposerCard: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var suggestions = MentionSuggestionModel()
    @State private var bodyText = ""
    @State private var isPublishing = false
    @State private var selectedTrack: MusicTrack?
    @State private var showTrackPicker = false
    @FocusState private var isFocused: Bool
    let onPublished: () -> Void

    var body: some View {
        Group {
            if session.user == nil {
                NavigationLink(destination: LoginView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(OpenlyTheme.accent)
                        Text("ماذا تريد أن تقول؟")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(OpenlyTheme.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 118)
                    .background(OpenlyTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    TextField("ماذا تريد أن تقول؟", text: $bodyText, axis: .vertical)
                        .focused($isFocused)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(OpenlyTheme.ink)
                        .lineLimit(2...5)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(OpenlyTheme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                        )
                        .onChange(of: bodyText) { value in
                            if value.count > postCharacterLimit {
                                bodyText = String(value.prefix(postCharacterLimit))
                            }
                            // SwiftUI's TextField hides the caret, so this
                            // compact composer reads the token at the end of the
                            // text. That covers typing, which is what happens
                            // here; the full-screen composer tracks the caret.
                            suggestions.update(
                                MentionParser.activeQuery(in: bodyText, caret: (bodyText as NSString).length)
                            )
                        }

                    MentionSuggestionBar(items: suggestions.items) { item in
                        guard let query = suggestions.activeQuery else { return }
                        let result = MentionParser.applyCompletion(
                            to: bodyText,
                            range: query.range,
                            code: item.publicCode
                        )
                        bodyText = result.text
                        suggestions.clear()
                    }

                    if let selectedTrack {
                        ComposerTrackChip(track: selectedTrack) { self.selectedTrack = nil }
                    } else {
                        HStack {
                            ComposerAddTrackButton { showTrackPicker = true }
                            Spacer()
                        }
                    }

                    HStack(spacing: 12) {
                        Text("\(bodyText.count) / \(postCharacterLimit)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)

                        Spacer()

                        Button {
                            Task { await publish() }
                        } label: {
                            HStack(spacing: 8) {
                                if isPublishing {
                                    ProgressView().tint(OpenlyTheme.accentForeground)
                                } else {
                                    Image(systemName: "paperplane")
                                    Text("نشر")
                                }
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(OpenlyTheme.accentForeground)
                            .padding(.horizontal, 20)
                            .frame(height: 42)
                            .background(OpenlyTheme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                        .opacity(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
                    }
                }
                .padding(18)
                .background(OpenlyTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(OpenlyTheme.lineStrong, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .sheet(isPresented: $showTrackPicker) {
            ComposerTrackPicker { selectedTrack = $0 }
                .environmentObject(session)
        }
    }

    @MainActor
    private func publish() async {
        guard session.requireLogin() else { return }
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPublishing = true
        do {
            _ = try await session.api.createPost(body: text, trackId: selectedTrack?.id)
            bodyText = ""
            selectedTrack = nil
            isFocused = false
            suggestions.clear()
            session.markFeedChanged()
            onPublished()
        } catch {
            session.alertMessage = error.localizedDescription
        }
        isPublishing = false
    }
}


struct NativeWriteView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var suggestions = MentionSuggestionModel()
    @State private var bodyText = ""
    @State private var selectedTrack: MusicTrack?
    @State private var showTrackPicker = false
    @State private var isPublishing = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New post")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.6)
                            .foregroundColor(OpenlyTheme.ink)
                        Text("Write first. Add context only if it helps.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(OpenlyTheme.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)

                VStack(spacing: 14) {
                    TextField("ماذا تريد أن تقول؟", text: $bodyText, axis: .vertical)
                        .focused($focused)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(OpenlyTheme.ink)
                        .lineLimit(7...14)
                        .padding(16)
                        .frame(minHeight: 190, alignment: .topLeading)
                        .background(OpenlyTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(OpenlyTheme.line, lineWidth: 1)
                        )
                        .onChange(of: bodyText) { value in
                            if value.count > postCharacterLimit {
                                bodyText = String(value.prefix(postCharacterLimit))
                            }
                            suggestions.update(
                                MentionParser.activeQuery(in: bodyText, caret: (bodyText as NSString).length)
                            )
                        }

                    MentionSuggestionBar(items: suggestions.items) { item in
                        guard let query = suggestions.activeQuery else { return }
                        let result = MentionParser.applyCompletion(
                            to: bodyText,
                            range: query.range,
                            code: item.publicCode
                        )
                        bodyText = result.text
                        suggestions.clear()
                    }

                    if let selectedTrack {
                        ComposerTrackChip(track: selectedTrack) { self.selectedTrack = nil }
                    } else {
                        HStack {
                            ComposerAddTrackButton { showTrackPicker = true }
                            Spacer()
                        }
                    }

                    HStack {
                        Text("\(bodyText.count) / \(postCharacterLimit)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)

                        Spacer()

                        Button {
                            Task { await publish() }
                        } label: {
                            if isPublishing {
                                ProgressView().tint(OpenlyTheme.accentForeground)
                                    .frame(width: 104, height: 46)
                            } else {
                                Text("Post")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(OpenlyTheme.accentForeground)
                                    .frame(width: 104, height: 46)
                            }
                        }
                        .background(OpenlyTheme.ink)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                        .opacity(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear { focused = true }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showTrackPicker) {
                ComposerTrackPicker { selectedTrack = $0 }
                    .environmentObject(session)
            }
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func publish() async {
        guard session.requireLogin() else { return }
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPublishing = true
        defer { isPublishing = false }

        do {
            _ = try await session.api.createPost(body: text, trackId: selectedTrack?.id)
            bodyText = ""
            selectedTrack = nil
            focused = false
            suggestions.clear()
            session.markFeedChanged()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct FeedSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpenlyTheme.surfaceSoft)
                    .frame(width: 94, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpenlyTheme.surfaceSoft)
                    .frame(width: 120, height: 12)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(OpenlyTheme.surfaceSoft)
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 4)
                .fill(OpenlyTheme.surfaceSoft)
                .frame(width: 210, height: 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(OpenlyTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
    }
}

struct OpenlySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(OpenlyTheme.muted)
            .padding(.horizontal, 20)
            .frame(height: 46)
            .background(Color.clear)
            .overlay(Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1.2))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PostCard: View {
    @EnvironmentObject private var session: AppSession
    let post: Post
    @State private var engagement: Engagement?
    @State private var likeInFlight = false
    @State private var bookmarkInFlight = false
    @State private var showReport = false

    var body: some View {
        let code = post.authorCode ?? "OPEN"

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                NavigationLink(destination: UserProfileView(code: code)) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color(hex: post.authorColor) ?? OpenlyTheme.accent)
                            .frame(width: 12, height: 12)
                        Text(code)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(OpenlyTheme.ink)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .buttonStyle(.plain)
                .disabled(post.authorCode == nil)

                Text("·")
                    .foregroundColor(OpenlyTheme.subtle)

                Text(OpenlyDate.relative(post.createdAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            // A mention inside the body is its own tap target, so the body is
            // no longer wrapped in the post link; the row below opens the
            // thread instead.
            MentionText(post.body, mentions: post.mentions)

            if let track = post.track {
                PostTrackAttachment(track: track)
            }

            HStack(spacing: 0) {
                NavigationLink(destination: PostDetailView(postID: post.id)) {
                    actionLabel(
                        icon: "bubble.left",
                        text: (post.commentCount ?? 0) > 0 ? "\(post.commentCount ?? 0) تعليق" : "تعليق",
                        active: false
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button { Task { await toggleLike() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasLiked == true ? "heart.fill" : "heart",
                        text: (engagement?.likeCount ?? 0) > 0 ? "\(engagement?.likeCount ?? 0) إعجاب" : "إعجاب",
                        active: engagement?.viewerHasLiked == true
                    )
                }
                .buttonStyle(.plain)
                .disabled(likeInFlight)
                .frame(maxWidth: .infinity)

                Button { Task { await toggleBookmark() } } label: {
                    actionLabel(
                        icon: engagement?.viewerHasBookmarked == true ? "bookmark.fill" : "bookmark",
                        text: engagement?.viewerHasBookmarked == true ? "محفوظ" : "حفظ",
                        active: engagement?.viewerHasBookmarked == true
                    )
                }
                .buttonStyle(.plain)
                .disabled(bookmarkInFlight)
                .frame(maxWidth: .infinity)

                Button { showReport = true } label: {
                    actionLabel(icon: "flag", text: "إبلاغ", active: false)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(OpenlyTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
        .task { await loadEngagement() }
        .sheet(isPresented: $showReport) { ReportView(postID: post.id) }
    }

    private func actionLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                 .font(.system(size: 14, weight: .regular))
            Text(text)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(active ? OpenlyTheme.accent : OpenlyTheme.muted)
        .contentShape(Rectangle())
    }

    @MainActor
    private func loadEngagement() async {
        do {
            let loaded = try await session.api.engagements(ids: [post.id]).first
            // An older request must never overwrite a tap that is already being
            // shown optimistically on screen.
            guard !likeInFlight && !bookmarkInFlight else { return }
            engagement = loaded
        } catch {
            // Engagement is secondary feed metadata. Keep the post usable when
            // this read fails instead of interrupting the whole timeline.
        }
    }

    @MainActor
    private func toggleLike() async {
        guard session.requireLogin(), !likeInFlight else { return }

        let current = engagement ?? Engagement(
            postId: post.id,
            likeCount: 0,
            viewerHasLiked: false,
            viewerHasBookmarked: false
        )
        let previousLiked = current.viewerHasLiked
        let previousCount = current.likeCount
        let next = !previousLiked

        // Native optimistic interaction: the heart and count change on the tap,
        // not after a network round trip.
        engagement = Engagement(
            postId: current.postId,
            likeCount: max(0, previousCount + (next ? 1 : -1)),
            viewerHasLiked: next,
            viewerHasBookmarked: current.viewerHasBookmarked
        )
        likeInFlight = true

        do {
            try await session.api.setLike(postID: post.id, enabled: next)
        } catch {
            // Roll back only the like fields so a bookmark tapped at nearly the
            // same time keeps its own optimistic state.
            let latest = engagement ?? current
            engagement = Engagement(
                postId: latest.postId,
                likeCount: previousCount,
                viewerHasLiked: previousLiked,
                viewerHasBookmarked: latest.viewerHasBookmarked
            )
            session.alertMessage = error.localizedDescription
        }

        likeInFlight = false
        // The server already acknowledged this optimistic state. Avoid an
        // immediate read-back request; the broker will refresh naturally when
        // this post is requested again.
    }

    @MainActor
    private func toggleBookmark() async {
        guard session.requireLogin(), !bookmarkInFlight else { return }

        let current = engagement ?? Engagement(
            postId: post.id,
            likeCount: 0,
            viewerHasLiked: false,
            viewerHasBookmarked: false
        )
        let previousBookmarked = current.viewerHasBookmarked
        let next = !previousBookmarked

        // Saving is optimistic for the same reason as liking: local UI first,
        // server confirmation second.
        engagement = Engagement(
            postId: current.postId,
            likeCount: current.likeCount,
            viewerHasLiked: current.viewerHasLiked,
            viewerHasBookmarked: next
        )
        bookmarkInFlight = true

        do {
            try await session.api.setBookmark(postID: post.id, enabled: next)
        } catch {
            let latest = engagement ?? current
            engagement = Engagement(
                postId: latest.postId,
                likeCount: latest.likeCount,
                viewerHasLiked: latest.viewerHasLiked,
                viewerHasBookmarked: previousBookmarked
            )
            session.alertMessage = error.localizedDescription
        }

        bookmarkInFlight = false
        // Keep the locally confirmed state instead of adding a second network
        // round trip after every save/unsave tap.
    }
}

private struct PostTrackAttachment: View {
    @ObservedObject private var previewPlayer = AudioPreviewPlayer.shared
    let track: PostTrack

    private var isPlaying: Bool {
        previewPlayer.activeTrackID == track.id
    }

    private var previewURL: String? {
        guard let value = track.previewUrl,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https" else { return nil }
        return value
    }

    private var actionLabel: LocalizedStringKey {
        isPlaying ? "post_track_pause" : "post_track_play"
    }

    var body: some View {
        HStack(spacing: 12) {
            PostTrackArtwork(url: track.artworkUrl)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let previewURL {
                Button {
                    previewPlayer.toggle(trackID: track.id, previewURL: previewURL)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OpenlyTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(OpenlyTheme.background)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(OpenlyTheme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(actionLabel))
            }
        }
        .padding(10)
        .background(OpenlyTheme.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OpenlyTheme.line, lineWidth: 1)
        )
    }
}

/// Shared with the composer's attachment picker, so a song looks identical
/// wherever it appears.
struct PostTrackArtwork: View {
    let url: String?

    var body: some View {
        Group {
            if let value = url,
               let remote = URL(string: value),
               remote.scheme?.lowercased() == "https" {
                AsyncImage(url: remote) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            OpenlyTheme.background
            Image(systemName: "music.note")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(OpenlyTheme.subtle)
        }
    }
}

/// Matches the server-side posts constraint.
let postCharacterLimit = 3000
let commentCharacterLimit = 2000
let reportDescriptionLimit = 1000

struct PostDetailView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var suggestions = MentionSuggestionModel()
    let postID: String
    @State private var detail: PostDetailResponse?
    @State private var commentText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Post")
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.6)
                                .foregroundColor(OpenlyTheme.ink)
                            Text("Conversation")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(OpenlyTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                        PostCard(post: detail.post)

                        HStack {
                            Text("Replies")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(OpenlyTheme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }

                        if detail.comments.isEmpty {
                            Text("لا توجد تعليقات بعد.")
                                .font(.system(size: 15))
                                .foregroundColor(OpenlyTheme.muted)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(detail.comments) { comment in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(Color(hex: comment.authorColor) ?? OpenlyTheme.accent)
                                                .frame(width: 10, height: 10)
                                            Text(comment.authorCode ?? "OPEN")
                                                .font(.system(size: 12, weight: .bold))
                                                .tracking(0.4)
                                                .foregroundColor(OpenlyTheme.ink)
                                                .environment(\.layoutDirection, .leftToRight)
                                        }
                                        Spacer()
                                        Text(OpenlyDate.relative(comment.createdAt))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(OpenlyTheme.subtle)
                                    }
                                    MentionText(
                                        comment.body,
                                        mentions: comment.mentions,
                                        font: .system(size: 17)
                                    )
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
                            }
                        }
                    }
                }
                .background(OpenlyTheme.background)
            } else if let errorMessage {
                EmptyState(icon: "exclamationmark.triangle", title: "تعذر فتح المنشور", message: errorMessage)
            } else {
                ProgressView("جارِ التحميل")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if detail != nil {
                VStack(spacing: 0) {
                MentionSuggestionBar(items: suggestions.items) { item in
                    guard let query = suggestions.activeQuery else { return }
                    let result = MentionParser.applyCompletion(
                        to: commentText,
                        range: query.range,
                        code: item.publicCode
                    )
                    commentText = result.text
                    suggestions.clear()
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        OpenlyFieldContainer {
                            TextField("Reply…", text: $commentText, axis: .vertical)
                                .foregroundColor(OpenlyTheme.ink)
                                .lineLimit(1...4)
                                .onChange(of: commentText) { value in
                                    if value.count > commentCharacterLimit {
                                        commentText = String(value.prefix(commentCharacterLimit))
                                    }
                                    suggestions.update(
                                        MentionParser.activeQuery(in: commentText, caret: (commentText as NSString).length)
                                    )
                                }
                        }
                        Text("\(commentText.count) / \(commentCharacterLimit)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(OpenlyTheme.subtle)
                            .environment(\.layoutDirection, .leftToRight)
                    }

                    Button { Task { await sendComment() } } label: {
                        if isSending {
                            ProgressView().tint(OpenlyTheme.accentForeground)
                        } else {
                            Text("Reply")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundColor(OpenlyTheme.accentForeground)
                    .frame(width: 74, height: 46)
                    .background(OpenlyTheme.ink)
                    .clipShape(Capsule())
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                }
                .background(OpenlyTheme.background)
                .overlay(alignment: .top) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        do { detail = try await session.api.post(id: postID) }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func sendComment() async {
        guard session.requireLogin() else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        do {
            try await session.api.addComment(postID: postID, body: text)
            commentText = ""
            suggestions.clear()
            await load()
        } catch { session.alertMessage = error.localizedDescription }
        isSending = false
    }
}

struct ReportView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let postID: String
    @State private var reason = "spam"
    @State private var description = ""
    @State private var isSending = false

    private let reasons = [
        ("spam", "محتوى مزعج أو مكرر"),
        ("harassment", "مضايقة"),
        ("hate", "خطاب كراهية"),
        ("threat", "تهديد"),
        ("sexual", "محتوى جنسي"),
        ("illegal", "محتوى غير قانوني"),
        ("other", "سبب آخر")
    ]

    var body: some View {
        NavigationView {
            Form {
                Picker("السبب", selection: $reason) {
                    ForEach(reasons, id: \.0) { Text($0.1).tag($0.0) }
                }
                Section("تفاصيل إضافية") {
                    TextEditor(text: $description)
                        .frame(minHeight: 110)
                        .onChange(of: description) { value in
                            if value.count > reportDescriptionLimit {
                                description = String(value.prefix(reportDescriptionLimit))
                            }
                        }
                    Text("\(description.count) / \(reportDescriptionLimit)")
                        .font(.caption)
                        .foregroundColor(OpenlyTheme.subtle)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .scrollContentBackground(.hidden)
            .background(OpenlyTheme.background)
            .navigationTitle("إبلاغ عن منشور")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إرسال") { Task { await submit() } }.disabled(isSending)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard session.requireLogin() else { dismiss(); return }
        isSending = true
        do {
            try await session.api.report(postID: postID, reason: reason, description: description)
            dismiss()
        } catch { session.alertMessage = error.localizedDescription }
        isSending = false
    }
}
