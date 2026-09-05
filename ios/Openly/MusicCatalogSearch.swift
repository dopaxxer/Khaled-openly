import Foundation
import Combine

/// One mutually exclusive search state for both native music pickers.
@MainActor
final class MusicCatalogSearch: ObservableObject {
    enum Phase: Equatable { case idle, loading, results, empty, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [MusicCatalogTrack] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var usingSavedCatalog = false
    private var generation = UUID()
    private let load: (String) async throws -> MusicCatalogResponse

    init(load: @escaping (String) async throws -> MusicCatalogResponse = {
        try await APIClient.shared.searchMusicCatalogResult(query: $0)
    }) { self.load = load }

    func cancel() {
        generation = UUID()
        results = []
        errorMessage = nil
        usingSavedCatalog = false
        phase = .idle
    }

    func search(_ query: String, debounce: UInt64 = 300_000_000) async {
        cancel()
        let token = generation
        let term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard term.count >= 2 else { return }
        phase = .loading
        do {
            if debounce > 0 { try await Task.sleep(nanoseconds: debounce) }
            try Task.checkCancellation()
            let response = try await load(term)
            guard token == generation, !Task.isCancelled else { return }
            results = response.items
            usingSavedCatalog = response.catalogUnavailable == true
            // An unavailable catalog must never be presented as “no results”.
            if usingSavedCatalog && results.isEmpty {
                throw APIError.server(OpenlyLocale.string("music_catalog_unavailable"))
            }
            phase = results.isEmpty ? .empty : .results
        } catch {
            guard token == generation else { return }
            if Task.isCancelled || error is CancellationError {
                cancel()
                return
            }
            results = []
            usingSavedCatalog = false
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }
}
