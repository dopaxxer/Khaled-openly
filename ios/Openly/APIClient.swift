import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "عنوان الخادم غير صالح."
        case .server(let message): return message
        case .invalidResponse: return "تعذر قراءة استجابة الخادم."
        }
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

struct OTPRequestResponse: Decodable {
    let ok: Bool
    let method: String
    let target: String
    let cooldownSeconds: Int
}

private actor EngagementBroker {
    private struct Entry {
        let value: Engagement
        let fetchedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var pendingIDs = Set<String>()
    private var waiters: [String: [CheckedContinuation<Engagement?, Error>]] = [:]
    private var flushTask: Task<Void, Never>?
    private let maxAge: TimeInterval = 20

    func values(
        for ids: [String],
        fetch: @escaping ([String]) async throws -> [Engagement]
    ) async throws -> [Engagement] {
        let unique = Array(Set(ids))
        return try await withThrowingTaskGroup(of: Engagement?.self) { group in
            for id in unique {
                group.addTask { try await self.value(for: id, fetch: fetch) }
            }
            var values: [Engagement] = []
            for try await value in group {
                if let value { values.append(value) }
            }
            return values
        }
    }

    private func value(
        for id: String,
        fetch: @escaping ([String]) async throws -> [Engagement]
    ) async throws -> Engagement? {
        if let entry = cache[id], Date().timeIntervalSince(entry.fetchedAt) < maxAge {
            return entry.value
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingIDs.insert(id)
            waiters[id, default: []].append(continuation)

            if flushTask == nil {
                flushTask = Task {
                    try? await Task.sleep(nanoseconds: 25_000_000)
                    await self.flush(fetch: fetch)
                }
            }
        }
    }

    private func flush(fetch: @escaping ([String]) async throws -> [Engagement]) async {
        let ids = Array(pendingIDs)
        pendingIDs.removeAll()
        flushTask = nil
        guard !ids.isEmpty else { return }

        do {
            let values = try await fetch(ids)
            let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.postId, $0) })
            let now = Date()

            for id in ids {
                let value = byID[id]
                if let value { cache[id] = Entry(value: value, fetchedAt: now) }
                let continuations = waiters.removeValue(forKey: id) ?? []
                continuations.forEach { $0.resume(returning: value) }
            }
        } catch {
            for id in ids {
                let continuations = waiters.removeValue(forKey: id) ?? []
                continuations.forEach { $0.resume(throwing: error) }
            }
        }
    }

    func invalidate(_ id: String) {
        cache.removeValue(forKey: id)
    }

    func clear() {
        cache.removeAll()
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://www.openly.ink/api/")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let engagementBroker = EngagementBroker()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    private func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let finalURL = parts.url else { throw APIError.invalidURL }
        return finalURL
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Openly-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw APIError.server("لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مجددًا.")
            case .timedOut:
                throw APIError.server("استغرق الاتصال وقتًا طويلًا. حاول مرة أخرى.")
            default:
                throw APIError.server("تعذر الاتصال بالخادم. حاول مرة أخرى.")
            }
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            NotificationCenter.default.post(name: .openlySessionExpired, object: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data).error)
                ?? "حدث خطأ في الخادم (\(http.statusCode))."
            throw APIError.server(message)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    func sessionUser() async throws -> UserSummary? {
        let response: SessionResponse = try await request("auth/me")
        return response.user
    }

    func requestOTP(method: String, email: String? = nil, phone: String? = nil) async throws -> OTPRequestResponse {
        var body: [String: Any] = ["method": method]
        if let email { body["email"] = email }
        if let phone { body["phone"] = phone }
        return try await request("auth/otp/request", method: "POST", body: body)
    }

    func verifyOTP(method: String, target: String, token: String) async throws {
        var body: [String: Any] = ["method": method, "token": token]
        if method == "phone" {
            body["phone"] = target
        } else {
            body["email"] = target
        }
        let _: ActionResponse = try await request("auth/otp/verify", method: "POST", body: body)
        await engagementBroker.clear()
    }

    func signInWithNativeToken(provider: String, idToken: String, accessToken: String? = nil, nonce: String? = nil) async throws {
        var body: [String: Any] = ["provider": provider, "idToken": idToken]
        if let accessToken { body["accessToken"] = accessToken }
        if let nonce { body["nonce"] = nonce }
        let _: ActionResponse = try await request("auth/native-token", method: "POST", body: body)
        await engagementBroker.clear()
    }

    func login(email: String, password: String) async throws {
        let _: ActionResponse = try await request("auth/login", method: "POST", body: ["email": email, "password": password])
        await engagementBroker.clear()
    }

    func register(email: String, password: String) async throws -> ActionResponse {
        try await request("auth/register", method: "POST", body: ["email": email, "password": password])
    }

    func verify(email: String, token: String) async throws {
        let _: ActionResponse = try await request("auth/verify", method: "POST", body: ["email": email, "token": token])
        await engagementBroker.clear()
    }

    func resendCode(email: String) async throws {
        let _: ActionResponse = try await request("auth/resend-code", method: "POST", body: ["email": email])
    }

    func requestPasswordReset(email: String) async throws {
        let _: ActionResponse = try await request("auth/request-password-reset", method: "POST", body: ["email": email])
    }

    func logout() async throws {
        let _: ActionResponse = try await request("auth/logout", method: "POST", body: [:])
        await engagementBroker.clear()
    }

    func feed(cursor: String? = nil, author: String? = nil) async throws -> FeedResponse {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let author { query.append(URLQueryItem(name: "author", value: author)) }
        return try await request("posts", query: query)
    }

    func createPost(body: String, trackId: String? = nil) async throws -> String? {
        var payload: [String: Any] = ["body": body]
        if let trackId {
            payload["trackId"] = trackId
        } else {
            payload["trackId"] = NSNull()
        }
        let response: ActionResponse = try await request("posts", method: "POST", body: payload)
        return response.id
    }

    func post(id: String) async throws -> PostDetailResponse {
        try await request("posts/\(id)")
    }

    func addComment(postID: String, body: String, parentID: String? = nil) async throws {
        var payload: [String: Any] = ["body": body]
        if let parentID { payload["parentCommentId"] = parentID }
        let _: ActionResponse = try await request("posts/\(postID)/comments", method: "POST", body: payload)
    }

    func engagements(ids: [String]) async throws -> [Engagement] {
        guard !ids.isEmpty else { return [] }
        return try await engagementBroker.values(for: ids) { [weak self] missingIDs in
            guard let self else { throw APIError.invalidResponse }
            let response: EngagementResponse = try await self.request(
                "engagement",
                query: [URLQueryItem(name: "ids", value: missingIDs.joined(separator: ","))]
            )
            return response.items
        }
    }

    func setLike(postID: String, enabled: Bool) async throws {
        let _: ActionResponse = try await request("posts/\(postID)/like", method: "POST", body: ["enabled": enabled])
        await engagementBroker.invalidate(postID)
    }

    func setBookmark(postID: String, enabled: Bool) async throws {
        let _: ActionResponse = try await request("posts/\(postID)/bookmark", method: "POST", body: ["enabled": enabled])
        await engagementBroker.invalidate(postID)
    }

    func search(_ query: String) async throws -> SearchResponse {
        try await request("search", query: [URLQueryItem(name: "q", value: query)])
    }

    func user(code: String) async throws -> UserSummary {
        let response: UserResponse = try await request("users/\(code)")
        return response.user
    }

    func setRelation(code: String, kind: String, enabled: Bool) async throws {
        let _: ActionResponse = try await request("users/\(code)/relation", method: "POST", body: ["kind": kind, "enabled": enabled])
    }

    func followersCount() async throws -> Int {
        let response: CountResponse = try await request("me/followers-count")
        return response.count
    }

    func following() async throws -> [UserSummary] {
        let response: FollowingResponse = try await request("me/following")
        return response.items
    }

    func notifications() async throws -> NotificationResponse {
        try await request("notifications")
    }

    /// Just the badge number. The full list is a much larger response than a
    /// tab badge needs, and the badge is refreshed far more often than the
    /// screen is opened.
    func unreadNotificationCount() async throws -> Int {
        let response: NotificationCountResponse = try await request("notifications/count")
        return response.unreadCount
    }

    func markNotificationsRead(ids: [String]) async throws {
        let _: ActionResponse = try await request("notifications", method: "PATCH", body: ["ids": ids])
    }

    func bookmarks() async throws -> [Post] {
        let response: FeedResponse = try await request("bookmarks")
        return response.items
    }

    func privacy() async throws -> [PrivacyRelation] {
        let response: PrivacyResponse = try await request("privacy")
        return response.items
    }

    // MARK: - Version 1 endpoints

    func mentionSuggestions(query: String) async throws -> [MentionRef] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return [] }
        let response: MentionSuggestionResponse = try await request(
            "v1/mentions/suggest",
            query: [URLQueryItem(name: "q", value: trimmed)]
        )
        return response.items
    }

    func resolveMentions(text: String) async throws -> [MentionRef] {
        let response: MentionSuggestionResponse = try await request(
            "v1/mentions/resolve",
            method: "POST",
            body: ["text": text]
        )
        return response.items
    }

    func searchMusicCatalog(query: String) async throws -> [MusicCatalogTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: MusicCatalogResponse = try await request(
            "v1/music/catalog",
            query: [URLQueryItem(name: "q", value: trimmed)]
        )
        return response.items
    }

    func addMusicTrack(_ track: MusicCatalogTrack) async throws -> MusicTrack {
        let response: MusicTrackCreateResponse = try await request(
            "v1/music/tracks",
            method: "POST",
            body: ["provider": track.provider, "externalId": track.externalId]
        )
        return response.track
    }

    func musicGenres(query: String? = nil) async throws -> [MusicGenre] {
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        let response: MusicGenresResponse = try await request("v1/music/genres", query: items)
        return response.items
    }

    func searchMusicArtists(query: String) async throws -> [MusicArtist] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: MusicArtistsResponse = try await request(
            "v1/music/artists",
            query: [URLQueryItem(name: "q", value: trimmed)]
        )
        return response.items
    }

    func addMusicArtist(name: String) async throws -> MusicArtist {
        let response: MusicArtistCreateResponse = try await request(
            "v1/music/artists",
            method: "POST",
            body: ["name": name.trimmingCharacters(in: .whitespacesAndNewlines)]
        )
        return response.artist
    }

    func musicProfile() async throws -> MusicProfile {
        let response: MusicProfileResponse = try await request("v1/music/visibility")
        return response.profile ?? .empty
    }

    func updateMusicSettings(
        discoveryOptIn: Bool,
        showTracks: Bool,
        showArtists: Bool,
        showGenres: Bool
    ) async throws -> MusicProfile {
        let response: MusicProfileResponse = try await request(
            "v1/music/visibility",
            method: "PUT",
            body: [
                "discoveryOptIn": discoveryOptIn,
                "showTracks": showTracks,
                "showArtists": showArtists,
                "showGenres": showGenres
            ]
        )
        return response.profile ?? .empty
    }

    func updateMusicTracks(ids: [String]) async throws -> MusicProfile {
        let response: MusicProfileResponse = try await request(
            "v1/music/preferences/tracks",
            method: "PUT",
            body: ["trackIds": ids]
        )
        return response.profile ?? .empty
    }

    func updateMusicArtists(ids: [String]) async throws -> MusicProfile {
        let response: MusicProfileResponse = try await request(
            "v1/music/preferences/artists",
            method: "PUT",
            body: ["artistIds": ids]
        )
        return response.profile ?? .empty
    }

    func updateMusicGenres(ids: [String]) async throws -> MusicProfile {
        let response: MusicProfileResponse = try await request(
            "v1/music/preferences/genres",
            method: "PUT",
            body: ["genreIds": ids]
        )
        return response.profile ?? .empty
    }

    func clearMusicPreferences() async throws -> MusicProfile {
        let response: MusicProfileResponse = try await request("v1/music/preferences", method: "DELETE")
        return response.profile ?? .empty
    }

    func discoverMusicPeople(
        artistID: String? = nil,
        genreID: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> MusicDiscoveryResponse {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let artistID { items.append(URLQueryItem(name: "artistId", value: artistID)) }
        if let genreID { items.append(URLQueryItem(name: "genreId", value: genreID)) }
        return try await request("v1/music/match-suggestions", query: items)
    }

    func setMusicMatchInterest(code: String, interested: Bool) async throws -> MusicMatchState {
        let response: MusicMatchStateResponse = try await request(
            "v1/music/match-interest",
            method: "PUT",
            body: ["publicCode": code, "interested": interested]
        )
        return response.state
    }

    func musicMatches(limit: Int = 50, offset: Int = 0) async throws -> MusicDiscoveryResponse {
        try await request(
            "v1/music/matches",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        )
    }

    func removeMusicMatch(code: String) async throws {
        let _: ActionResponse = try await request(
            "v1/music/matches",
            method: "DELETE",
            query: [URLQueryItem(name: "publicCode", value: code)]
        )
    }

    func publicMusicProfile(code: String) async throws -> PublicMusicProfile? {
        let response: PublicMusicProfileResponse = try await request("v1/users/\(code)/music")
        return response.profile
    }

    // MARK: - Common Ground interests

    func searchInterests(query: String, kind: InterestKind) async throws -> [InterestItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: InterestSearchResponse = try await request(
            "v1/interests",
            query: [
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "kind", value: kind.rawValue)
            ]
        )
        return response.items
    }

    func createTopicInterest(label: String) async throws -> InterestItem {
        let response: InterestItemResponse = try await request(
            "v1/interests",
            method: "POST",
            body: [
                "kind": InterestKind.topic.rawValue,
                "label": label.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
        )
        return response.item
    }

    func persistCatalogInterest(_ item: InterestItem) async throws -> InterestItem {
        guard let provider = item.provider, let externalId = item.externalId else {
            throw APIError.invalidResponse
        }
        let response: InterestItemResponse = try await request(
            "v1/interests",
            method: "POST",
            body: [
                "kind": item.kind,
                "provider": provider,
                "externalId": externalId
            ]
        )
        return response.item
    }

    func interestProfile() async throws -> InterestProfile {
        let response: InterestProfileResponse = try await request("v1/interests/preferences")
        return response.profile ?? .empty
    }

    func updateInterestProfile(
        discoveryOptIn: Bool,
        preferencesPublic: Bool,
        interestIDs: [String]
    ) async throws -> InterestProfile {
        let response: InterestProfileResponse = try await request(
            "v1/interests/preferences",
            method: "PUT",
            body: [
                "discoveryOptIn": discoveryOptIn,
                "preferencesPublic": preferencesPublic,
                "interestIds": interestIDs
            ]
        )
        return response.profile ?? .empty
    }

    func discoverInterestPeople(
        kind: InterestKind? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> InterestDiscoveryResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let kind {
            query.append(URLQueryItem(name: "kind", value: kind.rawValue))
        }
        return try await request("v1/interests/discover", query: query)
    }

    func publicInterestProfile(code: String) async throws -> PublicInterestProfile? {
        let response: PublicInterestProfileResponse = try await request("v1/users/\(code)/interests")
        return response.profile
    }

    func report(postID: String, reason: String, description: String) async throws {
        let _: ActionResponse = try await request(
            "reports",
            method: "POST",
            body: [
                "targetType": "post",
                "targetId": postID,
                "reason": reason,
                "description": description
            ]
        )
    }
}


extension Notification.Name {
    static let openlySessionExpired = Notification.Name("OpenlySessionExpired")
}
