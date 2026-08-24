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

/// SwiftUI can create several post rows at nearly the same time. Without a
/// broker every row fires its own `/engagement` request, and rows recreated by
/// scrolling repeat the same request. This actor coalesces calls arriving in a
/// short window and keeps a tiny per-post cache. Viewer-specific data never
/// leaves the process and is cleared whenever authentication changes.
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

    // Stable production API. Supabase credentials stay server-side on Vercel;
    // the native app only talks to this first-party JSON endpoint.
    private let baseURL = URL(string: "https://khaled-openly.vercel.app/api/")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let engagementBroker = EngagementBroker()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Openly-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
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

    func login(email: String, password: String) async throws {
        let _: ActionResponse = try await request(
            "auth/login",
            method: "POST",
            body: ["email": email, "password": password]
        )
        await engagementBroker.clear()
    }

    func register(email: String, password: String) async throws -> ActionResponse {
        try await request(
            "auth/register",
            method: "POST",
            body: ["email": email, "password": password]
        )
    }

    func verify(email: String, token: String) async throws {
        let _: ActionResponse = try await request(
            "auth/verify",
            method: "POST",
            body: ["email": email, "token": token]
        )
        await engagementBroker.clear()
    }

    func resendCode(email: String) async throws {
        let _: ActionResponse = try await request(
            "auth/resend-code",
            method: "POST",
            body: ["email": email]
        )
    }

    func requestPasswordReset(email: String) async throws {
        let _: ActionResponse = try await request(
            "auth/request-password-reset",
            method: "POST",
            body: ["email": email]
        )
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

    func createPost(body: String) async throws -> String? {
        let response: ActionResponse = try await request("posts", method: "POST", body: ["body": body])
        return response.id
    }

    func post(id: String) async throws -> PostDetailResponse {
        try await request("posts/\(id)")
    }

    func addComment(postID: String, body: String, parentID: String? = nil) async throws {
        var payload: [String: Any] = ["body": body]
        if let parentID { payload["parentCommentId"] = parentID }
        let _: ActionResponse = try await request(
            "posts/\(postID)/comments",
            method: "POST",
            body: payload
        )
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
        let _: ActionResponse = try await request(
            "posts/\(postID)/like",
            method: "POST",
            body: ["enabled": enabled]
        )
        await engagementBroker.invalidate(postID)
    }

    func setBookmark(postID: String, enabled: Bool) async throws {
        let _: ActionResponse = try await request(
            "posts/\(postID)/bookmark",
            method: "POST",
            body: ["enabled": enabled]
        )
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
        let _: ActionResponse = try await request(
            "users/\(code)/relation",
            method: "POST",
            body: ["kind": kind, "enabled": enabled]
        )
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

    func markNotificationsRead(ids: [String]) async throws {
        let _: ActionResponse = try await request(
            "notifications",
            method: "PATCH",
            body: ["ids": ids]
        )
    }

    func bookmarks() async throws -> [Post] {
        let response: FeedResponse = try await request("bookmarks")
        return response.items
    }

    func privacy() async throws -> [PrivacyRelation] {
        let response: PrivacyResponse = try await request("privacy")
        return response.items
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
