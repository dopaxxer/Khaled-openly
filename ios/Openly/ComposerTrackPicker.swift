import SwiftUI

/// Attaching one optional song to a post.
///
/// A catalog result is never stored as-is: `addMusicTrack` sends only the
/// provider and external id, and the server looks the song up again before it
/// writes canonical metadata. The composer therefore only ever holds a track id
/// the server minted, which is the same id `createPost` accepts.
struct ComposerTrackPicker: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let onPick: (MusicTrack) -> Void
    @StateObject var catalog = MusicCatalogSearch()

    @State private var query = ""
    @State private var attachingKey: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Music")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.6)
                        .foregroundColor(OpenlyTheme.ink)
                    Text("Add a song as context, not as the post itself.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OpenlyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

                searchField

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OpenlyTheme.danger)
                                .padding(.horizontal, 24)
                        }

                        if catalog.phase == .failed {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(catalog.errorMessage ?? OpenlyLocale.string("music_catalog_unavailable"))
                                    .foregroundColor(OpenlyTheme.danger)
                                    .accessibilityIdentifier("music.search.error")
                                Button("music_catalog_retry") {
                                    Task { await catalog.search(query, debounce: 0) }
                                }
                                .buttonStyle(OpenlyPressStyle())
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("music.search.retry")
                            }
                            .padding(.horizontal, 24)
                        } else if catalog.phase == .loading {
                            statusText("composer_track_searching")
                        } else if catalog.phase == .idle {
                            statusText("music_catalog_minimum")
                        } else if catalog.phase == .empty {
                            statusText("composer_track_empty")
                                .accessibilityIdentifier("music.search.empty")
                        }

                        if catalog.usingSavedCatalog {
                            statusText("music_catalog_saved")
                                .accessibilityIdentifier("music.search.saved")
                        }

                        ForEach(catalog.results) { track in
                            resultRow(track)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(OpenlyTheme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { OpenlyKeyboard.dismiss(); dismiss() }) {
                        Text("composer_track_cancel")
                            .foregroundColor(OpenlyTheme.accent)
                    }
                    .accessibilityIdentifier("music.search.close")
                }
            }
            .openlyKeyboardDismissal()
        }
        .navigationViewStyle(.stack)
        .task(id: query) { await catalog.search(query) }
        .onChange(of: query) { _ in errorMessage = nil }
        .onDisappear { catalog.cancel() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(OpenlyTheme.subtle)

            TextField("composer_track_search_placeholder", text: $query)
                .font(.system(size: 16))
                .foregroundColor(OpenlyTheme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("music.search.query")

            if !query.isEmpty {
                Button {
                    query = ""
                    catalog.cancel()
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OpenlyTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("music_catalog_clear"))
                .accessibilityIdentifier("music.search.clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(OpenlyTheme.surface)
        .overlay(
            Capsule()
                .stroke(OpenlyTheme.line, lineWidth: 1)
        )
        .clipShape(Capsule())
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private func statusText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 14))
            .foregroundColor(OpenlyTheme.muted)
            .padding(.horizontal, 18)
    }

    private func resultRow(_ track: MusicCatalogTrack) -> some View {
        Button {
            Task { await attach(track) }
        } label: {
            HStack(spacing: 12) {
                PostTrackArtwork(url: track.artworkUrl)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OpenlyTheme.ink)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundColor(OpenlyTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if attachingKey == track.id {
                    ProgressView().tint(OpenlyTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OpenlyTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(OpenlyTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(attachingKey != nil)
        .padding(.horizontal, 18)
    }

    @MainActor
    private func attach(_ catalogTrack: MusicCatalogTrack) async {
        guard attachingKey == nil else { return }
        attachingKey = catalogTrack.id
        errorMessage = nil
        do {
            let saved = try await session.api.addMusicTrack(catalogTrack)
            onPick(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        attachingKey = nil
    }
}

/// The attached song shown inside the composer, with the control that drops it.
struct ComposerTrackChip: View {
    let track: MusicTrack
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PostTrackArtwork(url: track.artworkUrl)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OpenlyTheme.ink)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(OpenlyTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(OpenlyTheme.muted)
                    .frame(width: 30, height: 30)
                    .background(OpenlyTheme.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("composer_track_remove"))
        }
        .padding(10)
        .background(OpenlyTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OpenlyTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The control that opens the picker when nothing is attached yet.
struct ComposerAddTrackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                Text("composer_add_track")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(OpenlyTheme.accent)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .overlay(
                Capsule().stroke(OpenlyTheme.lineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
