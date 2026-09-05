#if DEBUG
import Foundation

/// Deterministic UI fixtures; compiled out of every distributed Release IPA.
/// Every request is intercepted in this mode, including writes and presence.
actor OpenlyUITestAPI {
    static let shared = OpenlyUITestAPI()
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--openly-ui-fixture") }
    private var catalogRequests = 0
    private var sentMessages: [[String: Any]] = []

    private var user: [String: Any] { ["publicCode": "KHA9D", "identityColor": "#183D83", "createdAt": "2026-09-05T00:00:00Z"] }
    private var conversation: [String: Any] {
        ["conversationId": "11111111-1111-4111-8111-111111111111", "publicCode": "BLUE", "identityColor": "#527B67", "canMessage": true, "unreadCount": 0,
         "lastMessageBody": OpenlyLocale.currentLanguageCode == "ar" ? "لنتحدث عن الموسيقى" : "Let’s talk about music", "lastMessageAt": "2026-09-05T01:00:00Z"]
    }
    func response(path: String, method: String, query: [URLQueryItem], body: [String: Any]?) async throws -> Data {
        let ar = OpenlyLocale.currentLanguageCode == "ar"
        let payload: [String: Any]
        if path == "auth/me" { payload = ["user": user] }
        else if path == "posts" && method == "GET" {
            let texts = ar ? ["بعض الأغاني تعيدنا إلى لحظة لم ننساها.", "مساحة صغيرة للأفكار التي تستحق أن تُقال.", "ما الأغنية التي ترافق يومك؟"] : ["Some songs take us back to a moment we never forgot.", "A little space for thoughts worth sharing.", "What song is keeping you company today?"]
            payload = ["items": texts.enumerated().map { ["id": "post-\($0.offset)", "body": $0.element, "createdAt": "2026-09-05T01:00:00Z", "authorCode": "BLUE", "authorColor": "#527B67", "commentCount": 2] }]
        } else if path == "v1/music/catalog" {
            catalogRequests += 1
            if catalogRequests == 1 { throw APIError.server(OpenlyLocale.string("music_catalog_unavailable")) }
            payload = ["provider": "apple_music", "catalogUnavailable": true, "items": [["provider": "apple_music", "externalId": "1739659278", "title": "BLUE", "artist": "Billie Eilish"]]]
        } else if path == "v1/messages" {
            payload = ["items": [conversation], "total": 1, "limit": 50, "offset": 0, "hasMore": false]
        } else if path == "v1/messages/unread" || path == "notifications/count" { payload = ["unreadCount": 1] }
        else if path.hasPrefix("v1/messages/") && path.hasSuffix("/presence") {
            payload = ["online": true, "typing": false, "ok": true]
        } else if path.hasPrefix("v1/messages/") && path.hasSuffix("/read") {
            payload = ["ok": true, "readCount": 1]
        } else if path.hasPrefix("v1/messages/") && method == "POST" {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let message: [String: Any] = ["id": body?["clientNonce"] as? String ?? UUID().uuidString, "body": body?["body"] as? String ?? "", "createdAt": "2026-09-05T01:01:00Z", "senderCode": "KHA9D", "isMine": true]
            sentMessages.append(message)
            payload = ["message": message]
        } else if path.hasPrefix("v1/messages/") {
            payload = ["conversation": conversation, "items": sentMessages, "hasMore": false]
        } else if path == "notifications" && method == "GET" {
            payload = ["items": [["id": "notice-1", "kind": "like", "actorCode": "BLUE", "actorColor": "#527B67", "createdAt": "2026-09-05T01:00:00Z"]], "unreadCount": 1]
        } else if path == "search" { payload = ["posts": [], "users": [user]] }
        else if path == "me/followers-count" { payload = ["count": 0] }
        else { payload = ["ok": true, "items": []] }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
#endif
