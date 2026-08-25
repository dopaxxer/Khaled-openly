import Foundation

extension APIClient {
    /// Compatibility for the older MusicPreferencesView while the dedicated
    /// visibility screen exposes the new per-category controls.
    func updateMusicSettings(discoveryOptIn: Bool, preferencesPublic: Bool) async throws -> MusicProfile {
        try await updateMusicSettings(
            discoveryOptIn: discoveryOptIn,
            showTracks: preferencesPublic,
            showArtists: preferencesPublic,
            showGenres: preferencesPublic
        )
    }
}
