import Foundation

struct UserSummary: Codable, Identifiable, Hashable {
    var id: String { publicCode }
    let publicCode: String
    let identityColor: String
    let createdAt: String?
    let status: String?
    let bio: String?
    let viewerIsFollowing: Bool?
    let viewerHasMuted: Bool?
    let viewerHasBlocked: Bool?
    let isSelf: Bool?
}

struct Post: Codable, Identifiable, Hashable {
    let id: String
    let body: String
    let createdAt: String
    let authorCode: String?
    let authorColor: String?
    let commentCount: Int?
}

struct Comment: Codable, Identifiable, Hashable {
    let id: String
    let body: String
    let createdAt: String
    let parentCommentId: String?
    let authorCode: String?
    let authorColor: String?
}

struct Engagement: Codable, Identifiable, Hashable {
    var id: String { postId }
    let postId: String
    let likeCount: Int
    let viewerHasLiked: Bool
    let viewerHasBookmarked: Bool
}

struct NotificationItem: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let postId: String?
    let commentId: String?
    let actorCode: String?
    let actorColor: String?
    let readAt: String?
    let createdAt: String
}

struct PrivacyRelation: Codable, Identifiable, Hashable {
    var id: String { "\(kind)-\(publicCode)" }
    let kind: String
    let publicCode: String
    let identityColor: String
    let createdAt: String?
}

struct FeedResponse: Codable {
    let items: [Post]
    let nextCursor: String?
}

struct EngagementResponse: Codable {
    let items: [Engagement]
}

struct SearchResponse: Codable {
    let posts: [Post]
    let users: [UserSummary]
}

struct PostDetailResponse: Codable {
    let post: Post
    let comments: [Comment]
}

struct UserResponse: Codable {
    let user: UserSummary
}

struct SessionResponse: Codable {
    let user: UserSummary?
}

struct NotificationResponse: Codable {
    let items: [NotificationItem]
    let unreadCount: Int
}

struct FollowingResponse: Codable {
    let items: [UserSummary]
}

struct PrivacyResponse: Codable {
    let items: [PrivacyRelation]
}

struct CountResponse: Codable {
    let count: Int
}

struct ActionResponse: Codable {
    let ok: Bool?
    let id: String?
    let requiresEmailConfirmation: Bool?
    let email: String?
}

enum OpenlyDate {
    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallback = ISO8601DateFormatter()

    static func relative(_ value: String) -> String {
        guard let date = parser.date(from: value) ?? fallback.date(from: value) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func short(_ value: String?) -> String {
        guard let value,
              let date = parser.date(from: value) ?? fallback.date(from: value) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
