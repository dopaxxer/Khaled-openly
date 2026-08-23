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

final class APIClient {
    static let shared = APIClient()

    // Openly's native iOS client uses the deployed JSON API directly.
    private let baseURL = URL(string: "https://khaled-openly.vercel.app/api/")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
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
    }

    func resendCode(email: String) async throws {
        let _: ActionResponse = try await request(
            "auth/resend-code",
            method: "POST",
            body: ["email": email]
        )
    }

    func logout() async throws {
        let _: ActionResponse = try await request("auth/logout", method: "POST", body: [:])
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
        let response: EngagementResponse = try await request(
            "engagement",
            query: [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]
        )
        return response.items
    }

    func setLike(postID: String, enabled: Bool) async throws {
        let _: ActionResponse = try await request(
            "posts/\(postID)/like",
            method: "POST",
            body: ["enabled": enabled]
        )
    }

    func setBookmark(postID: String, enabled: Bool) async throws {
        let _: ActionResponse = try await request(
            "posts/\(postID)/bookmark",
            method: "POST",
            body: ["enabled": enabled]
        )
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
