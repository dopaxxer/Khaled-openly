import Foundation

struct PendingDirectMessage: Identifiable {
    let id: UUID
    let body: String
    var failed = false
    init(id: UUID = UUID(), body: String) { self.id = id; self.body = body }
}

enum DirectMessageCollection {
    static func mergeFetchedPage(_ current: [DirectMessage], _ fetched: [DirectMessage]) -> (items: [DirectMessage], cursor: String?) {
        // A send acknowledgement can be newer than incoming messages we have
        // not fetched yet. Only this fetched page may advance the read cursor.
        let orderedPage = merge([], fetched)
        let cursor = orderedPage.last.map { "\($0.createdAt)|\($0.id)" }
        return (merge(current, orderedPage), cursor)
    }

    static func merge(_ current: [DirectMessage], _ incoming: [DirectMessage]) -> [DirectMessage] {
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        incoming.forEach { byID[$0.id] = $0 }
        // Parse once per item; timestamps may contain different fractional widths.
        return byID.values.map { ($0, OpenlyDate.date(from: $0.createdAt) ?? .distantPast) }
            .sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }
            .map(\.0)
    }
}
