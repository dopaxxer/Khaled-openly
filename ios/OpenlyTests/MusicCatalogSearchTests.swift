import XCTest
@testable import Openly

@MainActor
final class MusicCatalogSearchTests: XCTestCase {
    private var blue: MusicCatalogTrack {
        MusicCatalogTrack(provider: "apple_music", externalId: "1739659278", title: "BLUE", artist: "Billie Eilish", album: nil, artworkUrl: nil, externalUrl: nil, previewUrl: nil, durationMs: nil, genre: nil)
    }

    func testFailureNeverBecomesNoResultsAndRetryClearsError() async {
        var count = 0
        let track = blue
        let model = MusicCatalogSearch { _ in
            count += 1
            if count == 1 { throw APIError.server("music_catalog_unavailable") }
            return MusicCatalogResponse(items: [track], provider: "apple_music")
        }
        await model.search("blue", debounce: 0)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertNotNil(model.errorMessage)
        await model.search("blue", debounce: 0)
        XCTAssertEqual(model.phase, .results)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.results.first?.title, "BLUE")
    }

    func testClearingOrOneCharacterDoesNotRequestCatalog() async {
        var count = 0
        let model = MusicCatalogSearch { _ in count += 1; throw APIError.invalidResponse }
        await model.search("blue", debounce: 0)
        await model.search("", debounce: 0)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.errorMessage)
        await model.search("b", debounce: 0)
        XCTAssertEqual(count, 1)
    }

    func testValidEmptyAndUnavailableEmptyAreDifferent() async {
        let empty = MusicCatalogSearch { _ in MusicCatalogResponse(items: [], provider: "apple_music") }
        await empty.search("zzzz", debounce: 0)
        XCTAssertEqual(empty.phase, .empty)
        let outage = MusicCatalogSearch { _ in MusicCatalogResponse(items: [], provider: "apple_music", catalogUnavailable: true) }
        await outage.search("zzzz", debounce: 0)
        XCTAssertEqual(outage.phase, .failed)
    }

    func testSavedResultsStayUsableAndIdentifyOutage() async {
        let track = blue
        let model = MusicCatalogSearch { _ in MusicCatalogResponse(items: [track], provider: "apple_music", catalogUnavailable: true) }
        await model.search("blue", debounce: 0)
        XCTAssertEqual(model.phase, .results)
        XCTAssertTrue(model.usingSavedCatalog)
    }

    func testLateResultCannotReturnAfterClearing() async {
        var continuation: CheckedContinuation<MusicCatalogResponse, Error>?
        let model = MusicCatalogSearch { _ in try await withCheckedThrowingContinuation { continuation = $0 } }
        let task = Task { await model.search("blue", debounce: 0) }
        while continuation == nil { await Task.yield() }
        await model.search("", debounce: 0)
        continuation?.resume(returning: MusicCatalogResponse(items: [blue], provider: "apple_music"))
        await task.value
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testOldServerResponseRemainsDecodable() throws {
        let response = try JSONDecoder().decode(MusicCatalogResponse.self, from: Data(#"{"items":[],"provider":"apple_music"}"#.utf8))
        XCTAssertNil(response.catalogUnavailable)
    }
}
