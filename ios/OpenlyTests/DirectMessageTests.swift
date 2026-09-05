import XCTest
@testable import Openly

final class DirectMessageTests: XCTestCase {
    func testMessagesDeduplicateAndUpdateReadReceipt() {
        let old = DirectMessage(id: "a", body: "hello", createdAt: "2026-09-05T01:00:00Z", readAt: nil, senderCode: "ABCD", senderColor: nil, isMine: true)
        let read = DirectMessage(id: "a", body: "hello", createdAt: old.createdAt, readAt: "2026-09-05T01:00:01Z", senderCode: "ABCD", senderColor: nil, isMine: true)
        let values = DirectMessageCollection.merge([old], [read])
        XCTAssertEqual(values.count, 1)
        XCTAssertNotNil(values[0].readAt)
    }

    func testFractionalWidthsDoNotMisorderMessages() {
        let first = DirectMessage(id: "a", body: "1", createdAt: "2026-09-05T01:00:00Z", readAt: nil, senderCode: "ABCD", senderColor: nil, isMine: false)
        let next = DirectMessage(id: "b", body: "2", createdAt: "2026-09-05T01:00:00.100Z", readAt: nil, senderCode: "ABCD", senderColor: nil, isMine: false)
        XCTAssertEqual(DirectMessageCollection.merge([next], [first]).map(\.id), ["a", "b"])
    }

    func testRetryKeepsTheOriginalIdempotencyKeyAndBody() {
        var item = PendingDirectMessage(body: "hello")
        let id = item.id
        item.failed = true
        item.failed = false
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.body, "hello")
    }

    func testFetchedPageDoesNotSkipIncomingMessagesBeforeNewerSend() {
        let acknowledged = DirectMessage(id: "sent", body: "My reply", createdAt: "2026-09-05T01:00:03Z", readAt: nil, senderCode: "SELF", senderColor: nil, isMine: true)
        let incoming = DirectMessage(id: "received", body: "Their message", createdAt: "2026-09-05T01:00:01Z", readAt: nil, senderCode: "PEER", senderColor: nil, isMine: false)
        let page = DirectMessageCollection.mergeFetchedPage([acknowledged], [incoming])
        XCTAssertEqual(page.items.map(\.id), ["received", "sent"])
        // Another incoming message at 01:00:02 must still be fetched next.
        XCTAssertEqual(page.cursor, "2026-09-05T01:00:01Z|received")
        let empty = DirectMessageCollection.mergeFetchedPage([acknowledged], [])
        XCTAssertNil(empty.cursor)
    }
}
