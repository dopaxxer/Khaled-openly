import SwiftUI

struct NativePublicMusicSection: View {
    let music: PublicMusicProfile

    private var tracks: [MusicTrack] { music.tracks ?? [] }
    private var hasContent: Bool {
        !tracks.isEmpty || !music.artists.isEmpty || !music.genres.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 14) {
                Text("الذوق الموسيقي")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(OpenlyTheme.ink)

                if !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الأغاني المفضلة")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(OpenlyTheme.muted)

                        ForEach(tracks) { track in
                            HStack(spacing: 12) {
                                artwork(track)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(OpenlyTheme.ink)
                                        .lineLimit(1)
                                    Text(track.album.map { "\(track.artist) · \($0)" } ?? track.artist)
                                        .font(.system(size: 12))
                                        .foregroundColor(OpenlyTheme.subtle)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                if !music.genres.isEmpty {
                    Text(music.genres.map(\.nameAr).joined(separator: "، "))
                        .font(.system(size: 15))
                        .foregroundColor(OpenlyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !music.artists.isEmpty {
                    (Text("الفنانون: ").foregroundColor(OpenlyTheme.muted)
                     + Text(music.artists.map(\.name).joined(separator: "، ")).foregroundColor(OpenlyTheme.ink))
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) { Rectangle().fill(OpenlyTheme.line).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func artwork(_ track: MusicTrack) -> some View {
        if let value = track.artworkUrl, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholder
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var placeholder: some View {
        ZStack {
            OpenlyTheme.surfaceSoft
            Image(systemName: "music.note")
                .foregroundColor(OpenlyTheme.muted)
        }
    }
}
