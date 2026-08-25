import Foundation

/// Artist/genre name folding, mirroring `private.normalize_music_name` in the
/// Supabase migration and `lib/musicNormalize.js` on the web.
///
/// The database is the authority — it recomputes the key on write and its
/// unique index is what actually prevents duplicates. This copy lets the app
/// tell the user "you already listed that" before a round trip.
enum MusicNormalize {
    static let artistNameMaxLength = 80
    static let maxArtistsPerProfile = 30
    static let maxGenresPerProfile = 15

    /// U+0629 -> U+0647, U+0649 -> U+064A, U+0671 -> U+0627. These three do not
    /// decompose under NFD, unlike the hamza forms whose hamza becomes a
    /// combining mark the strip step removes.
    private static let letterFolds: [(Character, Character)] = [
        ("\u{0629}", "\u{0647}"),
        ("\u{0649}", "\u{064A}"),
        ("\u{0671}", "\u{0627}")
    ]

    private static func isCombiningMark(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0300...0x036F, 0x0610...0x061A, 0x064B...0x065F, 0x06D6...0x06ED:
            return true
        case 0x0670, 0x0640:
            return true
        default:
            return false
        }
    }

    private static func isNameCharacter(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0061...0x007A, 0x0030...0x0039, 0x0600...0x06FF:
            return true
        default:
            return false
        }
    }

    /// The comparison key for a display name, or nil when nothing is left.
    static func key(_ value: String) -> String? {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return nil }

        var folded = lowered.decomposedStringWithCanonicalMapping
        for (from, to) in letterFolds {
            folded = folded.replacingOccurrences(of: String(from), with: String(to))
        }

        var output = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if isCombiningMark(scalar) { continue }
            if isNameCharacter(scalar) {
                if pendingSpace && !output.isEmpty { output.append(" ") }
                pendingSpace = false
                output.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }

        return output.isEmpty ? nil : output
    }

    /// True when two display names would collapse to the same catalog entry.
    static func isSameName(_ left: String, _ right: String) -> Bool {
        guard let a = key(left) else { return false }
        return a == key(right)
    }
}

/// The compatibility formula, mirroring `private.discover_music_people` and
/// `lib/musicScore.js`. The server computes the score that is displayed; this
/// exists so the rule is testable on the client and documented in one more
/// place that engineers actually read.
enum MusicScore {
    static let artistWeight = 3
    static let genreWeight = 1
    static let confidenceFloor = 6.0
    static let minSharedArtists = 1
    static let minSharedGenres = 2

    static func isEligible(sharedArtists: Int, sharedGenres: Int) -> Bool {
        sharedArtists >= minSharedArtists || sharedGenres >= minSharedGenres
    }

    static func compatibility(
        sharedArtists: Int,
        sharedGenres: Int,
        myArtists: Int,
        myGenres: Int,
        theirArtists: Int,
        theirGenres: Int
    ) -> Int {
        let raw = Double(artistWeight * sharedArtists + genreWeight * sharedGenres)
        let ceiling = Double(
            artistWeight * min(myArtists, theirArtists) + genreWeight * min(myGenres, theirGenres)
        )
        guard ceiling > 0, raw > 0 else { return 0 }

        let overlap = min(1.0, raw / ceiling)
        let confidence = min(1.0, raw / confidenceFloor)
        return Int((100 * overlap * confidence).rounded())
    }
}
