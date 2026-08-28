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

struct PostTrack: Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artworkUrl: String?
    let previewUrl: String?
    let externalUrl: String?
}

struct Post: Codable, Identifiable, Hashable {
    let id: String
    let body: String
    let createdAt: String
    let authorCode: String?
    let authorColor: String?
    let commentCount: Int?
    let mentions: [MentionRef]?
    let track: PostTrack?
}

struct Comment: Codable, Identifiable, Hashable {
    let id: String
    let body: String
    let createdAt: String
    let parentCommentId: String?
    let authorCode: String?
    let authorColor: String?
    let mentions: [MentionRef]?
}

struct MentionRef: Codable, Identifiable, Hashable {
    var id: String { publicCode }
    let publicCode: String
    let identityColor: String?
}

struct MentionSuggestionResponse: Codable {
    let items: [MentionRef]
}

struct MusicArtist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let listenerCount: Int?
}

struct MusicGenre: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    private let localizedArabicName: String

    enum CodingKeys: String, CodingKey {
        case id, slug, name
        case localizedArabicName = "nameAr"
    }

    init(id: String, slug: String, name: String, nameAr: String) {
        self.id = id
        self.slug = slug
        self.name = name
        self.localizedArabicName = nameAr
    }

    /// Existing views already read `nameAr`. Keep that API stable while making
    /// it respect the language selected inside Openly.
    var nameAr: String {
        OpenlyLocale.currentLanguageCode == "en" ? name : localizedArabicName
    }
}

struct MusicTrack: Codable, Identifiable, Hashable {
    let id: String
    let provider: String
    let externalId: String
    let title: String
    let artist: String
    let album: String?
    let artworkUrl: String?
    let externalUrl: String?
    let previewUrl: String?
    let durationMs: Int?
    let genre: String?
}

struct MusicCatalogTrack: Codable, Identifiable, Hashable {
    var id: String { "\(provider):\(externalId)" }
    let provider: String
    let externalId: String
    let title: String
    let artist: String
    let album: String?
    let artworkUrl: String?
    let externalUrl: String?
    let previewUrl: String?
    let durationMs: Int?
    let genre: String?
}

struct MusicProfile: Codable, Hashable {
    let discoveryOptIn: Bool
    let preferencesPublic: Bool
    let showTracks: Bool?
    let showArtists: Bool?
    let showGenres: Bool?
    let tracks: [MusicTrack]?
    let artists: [MusicArtist]
    let genres: [MusicGenre]

    var tracksArePublic: Bool { showTracks ?? preferencesPublic }
    var artistsArePublic: Bool { showArtists ?? preferencesPublic }
    var genresArePublic: Bool { showGenres ?? preferencesPublic }

    static let empty = MusicProfile(
        discoveryOptIn: false,
        preferencesPublic: false,
        showTracks: false,
        showArtists: false,
        showGenres: false,
        tracks: [],
        artists: [],
        genres: []
    )
}

struct PublicMusicProfile: Codable, Hashable {
    let publicCode: String
    let identityColor: String?
    let showTracks: Bool?
    let showArtists: Bool?
    let showGenres: Bool?
    let tracks: [MusicTrack]?
    let artists: [MusicArtist]
    let genres: [MusicGenre]
}

struct MusicMatch: Codable, Identifiable, Hashable {
    var id: String { publicCode }
    let publicCode: String
    let identityColor: String?
    let compatibility: Int
    let sharedArtistCount: Int
    let sharedGenreCount: Int
    let sharedArtists: [MusicArtist]
    let sharedGenres: [MusicGenre]
    var interested: Bool?
    var matched: Bool?
    var matchedAt: String?
}

struct MusicMatchState: Codable, Hashable {
    let publicCode: String
    let identityColor: String?
    let interested: Bool
    let matched: Bool
    let matchedAt: String?
}

struct MusicMatchStateResponse: Codable {
    let state: MusicMatchState
}

struct MusicProfileResponse: Codable {
    let profile: MusicProfile?
}

struct PublicMusicProfileResponse: Codable {
    let profile: PublicMusicProfile?
}

struct MusicArtistsResponse: Codable {
    let items: [MusicArtist]
}

struct MusicGenresResponse: Codable {
    let items: [MusicGenre]
}

struct MusicCatalogResponse: Codable {
    let items: [MusicCatalogTrack]
    let provider: String
}

struct MusicTrackCreateResponse: Codable {
    let track: MusicTrack
}

struct MusicArtistCreateResponse: Codable {
    let artist: MusicArtist
    let created: Bool
}

struct MusicDiscoveryResponse: Codable {
    let items: [MusicMatch]
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

enum InterestKind: String, Codable, CaseIterable, Identifiable {
    case topic
    case book
    case movie

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topic: return NSLocalizedString("مواضيع", comment: "")
        case .book: return NSLocalizedString("كتب", comment: "")
        case .movie: return NSLocalizedString("أفلام", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .topic: return "bubble.left.and.bubble.right"
        case .book: return "book"
        case .movie: return "film"
        }
    }
}

struct InterestItem: Codable, Identifiable, Hashable {
    let id: String
    let source: String?
    let kind: String
    let label: String
    let subtitle: String?
    let provider: String?
    let externalId: String?
    let artworkUrl: String?
    let releaseYear: Int?
    let externalUrl: String?
    let popularity: Int?
    let position: Int?

    var interestKind: InterestKind? { InterestKind(rawValue: kind) }
    var isCatalogResult: Bool { source == "catalog" }
}

struct InterestProfile: Codable, Hashable {
    let discoveryOptIn: Bool
    let preferencesPublic: Bool
    let items: [InterestItem]

    static let empty = InterestProfile(
        discoveryOptIn: false,
        preferencesPublic: false,
        items: []
    )
}

struct PublicInterestProfile: Codable, Hashable {
    let publicCode: String
    let identityColor: String?
    let items: [InterestItem]
}

struct InterestMatch: Codable, Identifiable, Hashable {
    var id: String { publicCode }
    let publicCode: String
    let identityColor: String?
    let compatibility: Int
    let sharedBookCount: Int
    let sharedMovieCount: Int
    let sharedTopicCount: Int
    let sharedItems: [InterestItem]
    let musicCompatibility: Int
}

struct InterestSearchResponse: Codable {
    let items: [InterestItem]
    let catalog: String?
    let catalogUnavailable: Bool?
}

struct InterestItemResponse: Codable {
    let item: InterestItem
}

struct InterestProfileResponse: Codable {
    let profile: InterestProfile?
}

struct PublicInterestProfileResponse: Codable {
    let profile: PublicInterestProfile?
}

struct InterestDiscoveryResponse: Codable {
    let items: [InterestMatch]
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct Engagement: Codable, Identifiable, Hashable {
    var id: String { postId }
    let postId: String
    let likeCount: Int
    let viewerHasLiked: Bool
    let viewerHasBookmarked: Bool
}

struct DirectConversation: Codable, Identifiable, Hashable {
    var id: String { conversationId }
    let conversationId: String
    let publicCode: String
    let identityColor: String?
    let createdAt: String?
    let lastMessageBody: String?
    let lastMessageAt: String?
    let lastMessageIsMine: Bool?
    let unreadCount: Int?
    let canMessage: Bool
}

struct DirectMessage: Codable, Identifiable, Hashable {
    let id: String
    let body: String
    let createdAt: String
    let readAt: String?
    let senderCode: String
    let senderColor: String?
    let isMine: Bool
}

struct DirectConversationListResponse: Codable {
    let items: [DirectConversation]
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct DirectConversationResponse: Codable {
    let conversation: DirectConversation
}

struct DirectThreadResponse: Codable {
    let conversation: DirectConversation
    let items: [DirectMessage]
    let nextCursor: String?
    let hasMore: Bool
}

struct DirectMessageResponse: Codable {
    let message: DirectMessage
}

struct DirectUnreadResponse: Codable {
    let unreadCount: Int
}

struct DirectReadResponse: Codable {
    let ok: Bool
    let readCount: Int
}

struct DirectPresenceResponse: Codable, Hashable {
    let online: Bool
    let typing: Bool
    let lastSeenAt: String?
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

struct ProfileUpdateResponse: Codable {
    let ok: Bool?
    let user: UserSummary
}

struct NotificationResponse: Codable {
    let items: [NotificationItem]
    let unreadCount: Int
}

struct NotificationCountResponse: Codable {
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

enum OpenlyLocale {
    static var currentLanguageCode: String {
        UserDefaults.standard.string(forKey: "openly.language") == "en" ? "en" : "ar"
    }

    static var locale: Locale {
        Locale(identifier: currentLanguageCode)
    }
}

enum OpenlyDate {
    static func date(from value: String) -> Date? {
        let normalized = Self.normalize(value)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: normalized) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: normalized) { return date }

        let posix = DateFormatter()
        posix.locale = Locale(identifier: "en_US_POSIX")
        posix.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ] {
            posix.dateFormat = format
            if let date = posix.date(from: value) ?? posix.date(from: normalized) {
                return date
            }
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        var s = value
        if s.hasSuffix("+00:00") {
            s = String(s.dropLast(6)) + "Z"
        }
        guard let dot = s.firstIndex(of: ".") else { return s }
        let fractionStart = s.index(after: dot)
        guard let end = s[fractionStart...].firstIndex(where: { !$0.isNumber }) else { return s }
        let fraction = s[fractionStart..<end]
        let millis = fraction.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)
        return String(s[..<fractionStart]) + millis + String(s[end...])
    }

    static func relative(_ value: String) -> String {
        guard let date = date(from: value) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = OpenlyLocale.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func short(_ value: String?) -> String {
        guard let value, let date = date(from: value) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = OpenlyLocale.locale
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
