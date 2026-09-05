# Architecture and behavior

Openly has two independent clients sharing one authenticated API and database. The website uses React, Vinext and reusable UI primitives. The iOS application uses SwiftUI with an iPad sidebar, iPhone tab bar, Keychain sessions, native photo selection, camera, audio recording, push registration and deep links. No WebView or PWA is presented as native.

## Persistence and authorization

The Worker handles `/api/*`. D1 contains 22 tables, with ordered SQL migrations in `drizzle/`. R2 is private: there are no public user-media URLs or long-lived signed URLs. Every media request goes through session validation and the same authorization rules as the associated content.

| Resource | Enforced rule |
| --- | --- |
| Posts and comments | Author visibility, post audience, Circle membership, blocking and Moment expiry |
| Private profiles | Public profile metadata remains discoverable; posts require an accepted follow |
| Follow requests | Only the requested account can accept or reject |
| Collections and drafts | Owner only; never included in a public profile |
| Conversations | Participant membership, blocking and messaging settings; recipient must accept requests |
| Message receipts | Recipient acknowledgement events; read timestamps only exposed when receipts are enabled |
| Circle moderation | Accepted owner/moderator membership; role changes require owner |
| Notifications | Recipient only; inaccessible/deleted targets are filtered |
| Media | Associated resource permission on every fetch, no-store response, expiry recorded independently on Moment media |

D1 has no PostgreSQL RLS. Authorization is enforced at the only exposed server boundary, using bound SQL parameters, fixed ACL predicates, validated identities and explicit ownership checks. The database itself is not exposed to clients. Do not provide D1 or R2 credentials to client applications.

Sessions are opaque random tokens stored as hashes on the server. Web sessions use HttpOnly SameSite cookies; native sessions use a Keychain bearer token. Passwords use salted PBKDF2-SHA256. Password recovery uses a generated, one-time-displayed recovery code, which rotates after recovery and invalidates existing sessions. Email delivery and email verification are not currently implemented. Do not promise email recovery in deployment copy.

## Genuine events and empty states

There is no seeded production activity. Test accounts use `example.test` in isolated in-memory databases. Following is chronological; For You uses shared public interests and actual prior likes. Ranking cursors include score, time and ID. Profile feeds put pinned posts first. Recommendation explanations include only known shared interests.

Messages use server-sent events with a database change check and a reconnecting stream. Delivery/read acknowledgements are separate authenticated writes by recipients. Retrying a message preserves its ID. Typing indicators expire and honor activity settings. A pending request permits one introduction before recipient approval. SSE is genuine server data, but its per-connection database checks need capacity planning before a large rollout.

Moment timestamps are created by the server, expire at 24 hours, and are enforced on content and media reads including the author. Expired media stays inaccessible even if the associated post is removed. Physical deletion/retention sweeps for expired and abandoned uploads are an operational follow-up; access expiry does not depend on such a sweep. Account deletion removes owned R2 objects and database rows; Circle owners must first delete their owned Circles.

## Music

The server searches Apple's iTunes catalog for real song metadata, artwork, links and available previews. Playback is initiated only by the user. When no preview is available, the product links to the music service. This does not grant full-song playback rights. Catalog availability, territorial behavior and service terms must be checked for the launch markets.

## Source boundaries

This branch is a new implementation and uses a new authentication/data store. It is not an in-place migration of the existing Supabase application in the repository's main branch. Existing account IDs, password hashes, media and histories are not imported. Keep the existing production deployment intact until a migration has been designed and authorized. The privately published review website has its own accounts and storage.

## Security and operations

Uploads are capped at 10 MB with byte signatures, allowed media types, streaming limits and a daily quota. Images are resized before upload by the web client. Requests are rate limited in the database. Sensitive writes reject cross-origin browser requests. Blocking is checked in both directions. Messages use HTTPS transport encryption; end-to-end encryption is not implemented or claimed.

Before a public rollout, perform an independent security review, production load tests, backup/restore drills and real-device acceptance testing. Configure operational handling for global reports via the moderator API and `MODERATOR_IDS`; Circle moderation has an in-product UI. These are release checks, not claims that such checks have already passed.
