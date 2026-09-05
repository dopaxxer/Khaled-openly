import SwiftUI

struct NativePublicMusicSection: View {
    let music: PublicMusicProfile

    private var tracks: [MusicTrack] { music.tracks ?? [] }
    private var hasContent: Bool {
        !tracks.isEmpty || !music.artists.isEmpty || !music.genres.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("الذوق الموسيقي")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(OpenlyTheme.ink)
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OpenlyTheme.subtle)
                }

                if !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الأغاني المفضلة")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(OpenlyTheme.muted)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(tracks.prefix(10)) { track in
                                    trackCard(track)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }

                if !music.artists.isEmpty || !music.genres.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !music.artists.isEmpty {
                            compactLine(
                                icon: "person.wave.2",
                                title: "الفنانون",
                                value: music.artists.map(\.name).joined(separator: " · ")
                            )
                        }

                        if !music.genres.isEmpty {
                            compactLine(
                                icon: "waveform",
                                title: "التصنيفات",
                                value: music.genres.map(\.nameAr).joined(separator: " · ")
                            )
                        }
                    }
                    .padding(14)
                    .background(OpenlyTheme.surfaceSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(OpenlyTheme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    private func trackCard(_ track: MusicTrack) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            artwork(track)
                .frame(width: 88, height: 88)

            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OpenlyTheme.ink)
                .lineLimit(1)
                .frame(width: 116, alignment: .leading)

            Text(track.artist)
                .font(.system(size: 11))
                .foregroundColor(OpenlyTheme.subtle)
                .lineLimit(1)
                .frame(width: 116, alignment: .leading)
        }
        .frame(width: 116, alignment: .leading)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func compactLine(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(OpenlyTheme.muted)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OpenlyTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
        } else {
            placeholder
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OpenlyTheme.line, lineWidth: 1))
        }
    }

    private var placeholder: some View {
        ZStack {
            OpenlyTheme.surfaceSoft
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(OpenlyTheme.muted)
        }
    }
}
