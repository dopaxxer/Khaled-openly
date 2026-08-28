import XCTest
@testable import Openly

/// Decoding tests for the shared web/iOS contract, plus the mention grammar
/// and music folding rules the app mirrors from the database.
///
/// The fixtures are the payloads the API actually returns; the expectations
/// were verified against the database. If a rule changes, change it in the
/// migration, lib/, and here together.
final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    func testAPIBaseURLNormalizesConfiguredHTTPSOrigin() {
        XCTAssertEqual(
            OpenlyAPIConfiguration.baseURL(from: "https://example.com/api").absoluteString,
            "https://example.com/api/"
        )
        XCTAssertEqual(
            OpenlyAPIConfiguration.baseURL(from: "https://example.com").absoluteString,
            "https://example.com/api/"
        )
    }

    func testAPIBaseURLRejectsUnsafeOrMalformedValues() {
        XCTAssertEqual(
            OpenlyAPIConfiguration.baseURL(from: "http://example.com/api/"),
            OpenlyAPIConfiguration.fallbackBaseURL
        )
        XCTAssertEqual(
            OpenlyAPIConfiguration.baseURL(from: "not a url"),
            OpenlyAPIConfiguration.fallbackBaseURL
        )
    }

    // MARK: - Decoding

    func testPostDecodesWithMentions() throws {
        let post = try decode(Post.self, """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "body": "hello @ABCD",
          "createdAt": "2026-08-24T12:00:00.000Z",
          "authorCode": "BCDE",
          "authorColor": "#3F7CAC",
          "commentCount": 2,
          "mentions": [{ "publicCode": "ABCD", "identityColor": "#B56576" }]
        }
        """)

        XCTAssertEqual(post.authorCode, "BCDE")
        XCTAssertEqual(post.mentions?.count, 1)
        XCTAssertEqual(post.mentions?.first?.publicCode, "ABCD")
    }

    func testPostStillDecodesWithoutMentions() throws {
        // Older responses, and any endpoint that has not been extended, must
        // keep working: mentions are additive.
        let post = try decode(Post.self, """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "body": "plain",
          "createdAt": "2026-08-24T12:00:00.000Z",
          "authorCode": "BCDE",
          "authorColor": "#3F7CAC",
          "commentCount": 0
        }
        """)
        XCTAssertNil(post.mentions)
    }

    func testPostDecodesWithoutTrackField() throws {
        let post = try decode(Post.self, """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "body": "plain text remains valid",
          "createdAt": "2026-08-24T12:00:00.000Z",
          "authorCode": "BCDE",
          "authorColor": "#3F7CAC",
          "commentCount": 0,
          "mentions": []
        }
        """)

        XCTAssertNil(post.track)
    }

    func testPostDecodesWithTrack() throws {
        let post = try decode(Post.self, """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "body": "a post with one song",
          "createdAt": "2026-08-24T12:00:00.000Z",
          "authorCode": "BCDE",
          "authorColor": "#3F7CAC",
          "commentCount": 0,
          "mentions": [],
          "track": {
            "id": "22222222-2222-4222-8222-222222222222",
            "title": "Test Song",
            "artist": "Test Artist",
            "artworkUrl": "https://is1-ssl.mzstatic.com/test.jpg",
            "previewUrl": "https://audio-ssl.mzstatic.com/test.m4a",
            "externalUrl": "https://music.apple.com/test"
          }
        }
        """)

        XCTAssertEqual(post.track?.id, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(post.track?.title, "Test Song")
        XCTAssertEqual(post.track?.artist, "Test Artist")
        XCTAssertEqual(post.track?.previewUrl, "https://audio-ssl.mzstatic.com/test.m4a")
    }

    func testCommentDecodesWithMentions() throws {
        let comment = try decode(Comment.self, """
        {
          "id": "22222222-2222-4222-8222-222222222222",
          "body": "reply to @ABCD",
          "createdAt": "2026-08-24T12:00:00.000Z",
          "parentCommentId": null,
          "authorCode": "BCDE",
          "authorColor": "#2A9D8F",
          "mentions": [{ "publicCode": "ABCD", "identityColor": null }]
        }
        """)
        XCTAssertEqual(comment.mentions?.first?.publicCode, "ABCD")
        XCTAssertNil(comment.mentions?.first?.identityColor)
    }

    func testMusicProfileDecodes() throws {
        let response = try decode(MusicProfileResponse.self, """
        {
          "profile": {
            "discoveryOptIn": true,
            "preferencesPublic": false,
            "artists": [{ "id": "33333333-3333-4333-8333-333333333333", "name": "Radiohead" }],
            "genres": [{
              "id": "44444444-4444-4444-8444-444444444444",
              "slug": "indie",
              "name": "Indie",
              "nameAr": "\u{625}\u{646}\u{62F}\u{64A}"
            }]
          }
        }
        """)

        let profile = try XCTUnwrap(response.profile)
        XCTAssertTrue(profile.discoveryOptIn)
        XCTAssertFalse(profile.preferencesPublic)
        XCTAssertEqual(profile.artists.first?.name, "Radiohead")
        XCTAssertEqual(profile.genres.first?.slug, "indie")
    }

    func testDiscoveryResponseDecodes() throws {
        let response = try decode(MusicDiscoveryResponse.self, """
        {
          "items": [{
            "publicCode": "BBBB",
            "identityColor": "#2A9D8F",
            "compatibility": 100,
            "sharedArtistCount": 2,
            "sharedGenreCount": 2,
            "sharedArtists": [
              { "id": "33333333-3333-4333-8333-333333333333", "name": "Radiohead" }
            ],
            "sharedGenres": [
              { "id": "44444444-4444-4444-8444-444444444444", "slug": "rock", "name": "Rock", "nameAr": "R" }
            ]
          }],
          "total": 2,
          "limit": 20,
          "offset": 0,
          "hasMore": false
        }
        """)

        XCTAssertEqual(response.total, 2)
        XCTAssertFalse(response.hasMore)
        let match = try XCTUnwrap(response.items.first)
        XCTAssertEqual(match.compatibility, 100)
        XCTAssertEqual(match.sharedArtists.first?.name, "Radiohead")
        // The card explains the score from these counts, so they must survive
        // decoding exactly.
        XCTAssertEqual(match.sharedArtistCount, 2)
        XCTAssertEqual(match.sharedGenreCount, 2)
    }

    func testUnpublishedMusicProfileDecodesAsAbsent() throws {
        let response = try decode(PublicMusicProfileResponse.self, "{ \"profile\": null }")
        XCTAssertNil(response.profile)
    }

    func testInterestCatalogAndDiscoveryResponsesDecode() throws {
        let search = try decode(InterestSearchResponse.self, """
        {
          "items": [{
            "id": "catalog:apple_movies:123",
            "source": "catalog",
            "kind": "movie",
            "label": "Interstellar",
            "subtitle": "Christopher Nolan",
            "provider": "apple_movies",
            "externalId": "123",
            "artworkUrl": "https://is1-ssl.mzstatic.com/poster.jpg",
            "releaseYear": 2014,
            "externalUrl": "https://tv.apple.com/movie/example",
            "popularity": 2
          }],
          "catalog": "apple"
        }
        """)

        let item = try XCTUnwrap(search.items.first)
        XCTAssertTrue(item.isCatalogResult)
        XCTAssertEqual(item.interestKind, .movie)
        XCTAssertEqual(item.releaseYear, 2014)

        let discovery = try decode(InterestDiscoveryResponse.self, """
        {
          "items": [{
            "publicCode": "BCDE",
            "identityColor": "#2A9D8F",
            "compatibility": 82,
            "sharedBookCount": 1,
            "sharedMovieCount": 1,
            "sharedTopicCount": 2,
            "sharedItems": [{
              "id": "55555555-5555-4555-8555-555555555555",
              "source": "saved",
              "kind": "topic",
              "label": "علم النفس",
              "subtitle": null,
              "provider": null,
              "externalId": null,
              "artworkUrl": null,
              "releaseYear": null,
              "externalUrl": null
            }],
            "musicCompatibility": 40
          }],
          "total": 1,
          "limit": 20,
          "offset": 0,
          "hasMore": false
        }
        """)

        XCTAssertEqual(discovery.items.first?.compatibility, 82)
        XCTAssertEqual(discovery.items.first?.sharedTopicCount, 2)
        XCTAssertEqual(discovery.items.first?.musicCompatibility, 40)
    }

    func testDirectMessageContractsDecode() throws {
        let start = try decode(DirectConversationResponse.self, """
        {
          "conversation": {
            "conversationId": "11111111-1111-4111-8111-111111111111",
            "publicCode": "AB23",
            "identityColor": "#3F7CAC",
            "canMessage": true
          }
        }
        """)
        XCTAssertEqual(start.conversation.publicCode, "AB23")
        XCTAssertNil(start.conversation.lastMessageBody)
        XCTAssertTrue(start.conversation.canMessage)

        let thread = try decode(DirectThreadResponse.self, """
        {
          "conversation": {
            "conversationId": "11111111-1111-4111-8111-111111111111",
            "publicCode": "AB23",
            "identityColor": "#3F7CAC",
            "createdAt": "2026-08-28T12:00:00.000Z",
            "unreadCount": 1,
            "canMessage": true
          },
          "items": [{
            "id": "22222222-2222-4222-8222-222222222222",
            "body": "مرحبا",
            "createdAt": "2026-08-28T12:01:00.000Z",
            "readAt": null,
            "senderCode": "AB23",
            "senderColor": "#3F7CAC",
            "isMine": false
          }],
          "nextCursor": null,
          "hasMore": false
        }
        """)
        XCTAssertEqual(thread.items.first?.body, "مرحبا")
        XCTAssertEqual(thread.items.first?.isMine, false)
        XCTAssertEqual(thread.conversation.unreadCount, 1)
    }

    // MARK: - Mention grammar (parity with SQL and lib/mentions.js)

    func testMentionParserMatchesTheSharedFixtures() {
        let fixtures: [(String, [String])] = [
            ("hi @ABCD and @ef2h, mail me@example.com, @TOOLONGCODE9, @ABCI", ["ABCD", "EF2H"]),
            ("@AAAA @BBBB", ["AAAA", "BBBB"]),
            ("@AAAA@BBBB", ["AAAA"]),
            ("start@AAAA", []),
            ("@AAA", []),
            ("@AAAAAAAA", ["AAAAAAAA"]),
            ("@AAAAAAAAA", []),
            ("line one\n@BBBB second line", ["BBBB"]),
            ("@aaaa @AAAA duplicate", ["AAAA"]),
            ("@AAAA_underscore", []),
            ("email name@AAAA.com", []),
            ("@@AAAA", []),
            ("<script>@AAAA</script>", ["AAAA"])
        ]

        for (input, expected) in fixtures {
            XCTAssertEqual(MentionParser.codes(in: input), expected, "input: \(input)")
        }
    }

    func testOnlyResolvedCodesBecomeMentions() {
        let segments = MentionParser.segments(in: "hi @ABCD and @ZZZZ", resolved: ["ABCD"])
        XCTAssertEqual(segments, [
            .text("hi "),
            .mention(display: "@ABCD", code: "ABCD"),
            .text(" and @ZZZZ")
        ])

        // Nothing resolved leaves the text untouched.
        XCTAssertEqual(MentionParser.segments(in: "hi @ABCD", resolved: []), [.text("hi @ABCD")])
    }

    func testSegmentsReassembleToTheOriginalText() {
        let inputs = [
            "hi @ABCD and @BCDE done",
            "@ABCD",
            "no mentions",
            "punctuation (@ABCD), then @BCDE!"
        ]
        for input in inputs {
            let rebuilt = MentionParser.segments(in: input, resolved: ["ABCD", "BCDE"])
                .map { segment -> String in
                    switch segment {
                    case .text(let value): return value
                    case .mention(let display, _): return display
                    }
                }
                .joined()
            XCTAssertEqual(rebuilt, input)
        }
    }

    func testComposerFindsTheTokenUnderTheCaret() {
        let query = MentionParser.activeQuery(in: "hello @ab", caret: 9)
        XCTAssertEqual(query?.query, "AB")
        XCTAssertEqual(query?.range, NSRange(location: 6, length: 3))

        // Caret before the token, inside an e-mail, and past the code length.
        XCTAssertNil(MentionParser.activeQuery(in: "hello @ab", caret: 5))
        XCTAssertNil(MentionParser.activeQuery(in: "name@example", caret: 12))
        XCTAssertNil(MentionParser.activeQuery(in: "@ABCDEFGHI", caret: 10))
    }

    func testChoosingASuggestionInsertsTheCanonicalCode() throws {
        let query = try XCTUnwrap(MentionParser.activeQuery(in: "hello @ab", caret: 9))
        let result = MentionParser.applyCompletion(to: "hello @ab", range: query.range, code: "abcd")
        XCTAssertEqual(result.text, "hello @ABCD ")
        XCTAssertEqual(result.caret, 12)
    }

    // MARK: - Navigation

    func testTappingAMentionResolvesToThatProfile() throws {
        let url = try XCTUnwrap(MentionParser.mentionURL(for: "abcd"))
        XCTAssertEqual(url.absoluteString, "openly-mention://ABCD")
        XCTAssertEqual(MentionParser.profileCode(fromMentionURL: url), "ABCD")
    }

    func testForeignLinksAreNotTreatedAsMentions() throws {
        // Anything that is not our scheme must fall through to the system, so
        // a link in a body can never be turned into an in-app profile push.
        for raw in ["https://example.com/ABCD", "openly-mention://not-a-code", "mailto:a@b.co"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertNil(MentionParser.profileCode(fromMentionURL: url), "raw: \(raw)")
        }
    }

    // MARK: - Music folding (parity with SQL and lib/musicNormalize.js)

    func testMusicNameFoldingMatchesTheSharedFixtures() {
        let fixtures: [(String, String)] = [
        ("Radiohead", "radiohead"),
        ("  RADIO  head!! ", "radio head"),
        ("Sigur R\u{F3}s", "sigur ros"),
        ("sigur ros", "sigur ros"),
        ("Beyonc\u{E9}", "beyonce"),
        ("AC/DC", "ac dc"),
        ("\u{641}\u{64A}\u{631}\u{648}\u{632}", "\u{641}\u{64A}\u{631}\u{648}\u{632}"),
        ("\u{641}\u{64A}\u{640}\u{640}\u{631}\u{648}\u{632}", "\u{641}\u{64A}\u{631}\u{648}\u{632}"),
        ("\u{639}\u{64E}\u{645}\u{652}\u{631}\u{648} \u{62F}\u{64A}\u{627}\u{628}", "\u{639}\u{645}\u{631}\u{648} \u{62F}\u{64A}\u{627}\u{628}"),
        ("\u{639}\u{645}\u{631}\u{648} \u{62F}\u{64A}\u{627}\u{628}", "\u{639}\u{645}\u{631}\u{648} \u{62F}\u{64A}\u{627}\u{628}"),
        ("\u{623}\u{645} \u{643}\u{644}\u{62B}\u{648}\u{645}", "\u{627}\u{645} \u{643}\u{644}\u{62B}\u{648}\u{645}"),
        ("\u{627}\u{645} \u{643}\u{644}\u{62B}\u{648}\u{645}", "\u{627}\u{645} \u{643}\u{644}\u{62B}\u{648}\u{645}"),
        ("\u{645}\u{635}\u{637}\u{641}\u{649}", "\u{645}\u{635}\u{637}\u{641}\u{64A}"),
        ("\u{645}\u{635}\u{637}\u{641}\u{64A}", "\u{645}\u{635}\u{637}\u{641}\u{64A}")
        ]

        for (input, expected) in fixtures {
            XCTAssertEqual(MusicNormalize.key(input), expected, "input: \(input)")
        }

        XCTAssertNil(MusicNormalize.key("!!!"))
        XCTAssertNil(MusicNormalize.key("   "))
        XCTAssertNil(MusicNormalize.key(""))
    }

    func testVariantsThatWouldDuplicateAnArtistCollapse() {
        XCTAssertTrue(MusicNormalize.isSameName("Sigur R\u{F3}s", "Sigur Ros"))
        XCTAssertTrue(MusicNormalize.isSameName("Radiohead", "  RADIOHEAD!! "))
        XCTAssertFalse(MusicNormalize.isSameName("Radiohead", "Radio Head"))
    }

    func testCompatibilityMatchesTheServerScores() {
        // The same fixtures the database produced: 100 and 38.
        XCTAssertEqual(
            MusicScore.compatibility(
                sharedArtists: 2, sharedGenres: 2,
                myArtists: 3, myGenres: 3, theirArtists: 2, theirGenres: 2
            ),
            100
        )
        XCTAssertEqual(
            MusicScore.compatibility(
                sharedArtists: 1, sharedGenres: 0,
                myArtists: 3, myGenres: 3, theirArtists: 1, theirGenres: 1
            ),
            38
        )
    }

    func testEmptyProfilesScoreZeroInsteadOfDividingByZero() {
        XCTAssertEqual(
            MusicScore.compatibility(
                sharedArtists: 0, sharedGenres: 0,
                myArtists: 0, myGenres: 0, theirArtists: 0, theirGenres: 0
            ),
            0
        )
        XCTAssertEqual(
            MusicScore.compatibility(
                sharedArtists: 3, sharedGenres: 3,
                myArtists: 0, myGenres: 0, theirArtists: 5, theirGenres: 5
            ),
            0
        )
    }

    func testASingleWeakMatchNeverReadsAsAStrongOne() {
        XCTAssertEqual(
            MusicScore.compatibility(
                sharedArtists: 0, sharedGenres: 1,
                myArtists: 0, myGenres: 1, theirArtists: 0, theirGenres: 1
            ),
            17
        )
        XCTAssertFalse(MusicScore.isEligible(sharedArtists: 0, sharedGenres: 1))
        XCTAssertTrue(MusicScore.isEligible(sharedArtists: 1, sharedGenres: 0))
        XCTAssertTrue(MusicScore.isEligible(sharedArtists: 0, sharedGenres: 2))
    }
}
