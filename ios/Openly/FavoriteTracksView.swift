import SwiftUI

/// A provider-backed favorite song picker. Search results are never persisted
/// directly: `addMusicTrack` sends only provider + external id and the server
/// looks the song up again before writing canonical title/artwork metadata.
struct FavoriteTracksView: View {
    @EnvironmentObject private var session: AppSession

    @State private var tracks: [MusicTrack] = []
    @State private var query = ""
    @State private var results: [MusicCatalogTrack] = []
    @State private var isLoading = true
    @State private var isSearching = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if session.user == nil {
                LoginRequiredView(message: "سجّل الدخول لاختيار أغانيك المفضلة.")
            } else if isLoading {
                ProgressView("جارِ تحميل الأغاني")
                    .tint(OpenlyTheme.accent)
                    .foregroundColor(OpenlyTheme.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("الأغاني المفضلة")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(OpenlyTheme.ink)
                            Text("ابحث باسم الأغنية أو الفنان واختر النتيجة الأصلية مع الغلاف والألبوم.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OpenlyTheme.muted)
                                .lineSpacing(4)
                        }

                        TextField("ابحث عن أغنية…", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .background(OpenlyTheme.surfaceSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .autocorrectionDisabled()
                            .onChange(of: query) { scheduleSearch($0) }

                        if isSearching {
                            HStack(spacing: 8) {
                                ProgressView().tint(OpenlyTheme.accent)
                                Text("جارِ البحث في الكتالوج…")
                                    .font(.system(size: 13))
                                    .foregroundColor(OpenlyTheme.subtle)
                            }
                        }

                        if !results.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(results) { track in
                                    Button {
                                        Task { await add(track) }
                                    } label: {
                                        CatalogTrackRow(
                                            track: track,
                                            selected: tracks.contains { $0.provider == track.provider && $0.externalId == track.externalId }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(
                                        busy ||
                                        tracks.count >= MusicNormalize.maxTracksPerProfile ||
                                        tracks.contains { $0.provider == track.provider && $0.externalId == track.externalId }
                                    )

                                    if track.id != results.last?.id {
                                        Divider().background(OpenlyTheme.line)
                                    }
                                }
                            }
                            .background(OpenlyTheme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
                        }

                        HStack {
                            Text("اختياراتي")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(OpenlyTheme.ink)
                            Spacer()
                            Text("\(tracks.count) / \(MusicNormalize.maxTracksPerProfile)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(OpenlyTheme.subtle)
                                .environment(\.layoutDirection, .leftToRight)
                        }

                        if tracks.isEmpty {
                            Text("لم تختر أي أغنية بعد.")
                                .font(.system(size: 14))
                                .foregroundColor(OpenlyTheme.subtle)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                    SavedTrackRow(
                                        track: track,
                                        canMoveUp: index > 0,
                                        canMoveDown: index < tracks.count - 1,
                                        disabled: busy,
                                        moveUp: { Task { await move(index, by: -1) } },
                                        moveDown: { Task { await move(index, by: 1) } },
                                        remove: { Task { await remove(track) } }
                                    )
                                    if track.id != tracks.last?.id {
                                        Divider().background(OpenlyTheme.line)
                                    }
                                }
                            }
                            .background(OpenlyTheme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OpenlyTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Openly لا يربط حساب Apple Music ولا يجمع سجل استماعك. نحفظ فقط الأغاني التي تختارها هنا.")
                            .font(.system(size: 12))
                            .foregroundColor(OpenlyTheme.subtle)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .refreshable { await load() }
            }
        }
        .background(OpenlyTheme.background.ignoresSafeArea())
        .navigationTitle("الأغاني المفضلة")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OpenlyTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { if session.user != nil { await load() } }
        .onDisappear { searchTask?.cancel() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await session.api.musicProfile()
            tracks = profile.tracks ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            do {
                let found = try await session.api.searchMusicCatalog(query: term)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = found
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = []
                    isSearching = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func add(_ catalogTrack: MusicCatalogTrack) async {
        guard tracks.count < MusicNormalize.maxTracksPerProfile else {
            errorMessage = "الحد الأقصى \(MusicNormalize.maxTracksPerProfile) أغنية."
            return
        }
        guard !tracks.contains(where: {
            $0.provider == catalogTrack.provider && $0.externalId == catalogTrack.externalId
        }) else { return }

        busy = true
        errorMessage = nil
        do {
            let saved = try await session.api.addMusicTrack(catalogTrack)
            let next = tracks + [saved]
            let profile = try await session.api.updateMusicTracks(ids: next.map(\.id))
            tracks = profile.tracks ?? next
            query = ""
            results = []
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    @MainActor
    private func remove(_ track: MusicTrack) async {
        await save(tracks.filter { $0.id != track.id })
    }

    @MainActor
    private func move(_ index: Int, by delta: Int) async {
        var next = tracks
        let target = index + delta
        guard target >= 0, target < next.count else { return }
        next.swapAt(index, target)
        await save(next)
    }

    @MainActor
    private func save(_ next: [MusicTrack]) async {
        busy = true
        errorMessage = nil
        do {
            let profile = try await session.api.updateMusicTracks(ids: next.map(\.id))
            tracks = profile.tracks ?? next
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }
}

private struct CatalogTrackRow: View {
    let track: MusicCatalogTrack
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            TrackArtwork(url: track.artworkUrl, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                    .lineLimit(1)
                Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(selected ? OpenlyTheme.subtle : OpenlyTheme.accent)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }
}

private struct SavedTrackRow: View {
    let track: MusicTrack
    let canMoveUp: Bool
    let canMoveDown: Bool
    let disabled: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TrackArtwork(url: track.artworkUrl, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(OpenlyTheme.subtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            miniButton("chevron.up", disabled: disabled || !canMoveUp, action: moveUp)
            miniButton("chevron.down", disabled: disabled || !canMoveDown, action: moveDown)
            miniButton("xmark", disabled: disabled, danger: true, action: remove)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 70)
    }

    private func miniButton(_ icon: String, disabled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(danger ? OpenlyTheme.danger : OpenlyTheme.muted)
                .frame(width: 34, height: 34)
                .background(OpenlyTheme.surfaceSoft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

private struct TrackArtwork: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let remote = URL(string: url) {
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            OpenlyTheme.surfaceSoft
            Image(systemName: "music.note")
                .foregroundColor(OpenlyTheme.subtle)
        }
    }
}
