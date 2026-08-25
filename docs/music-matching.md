# Mutual music matching

Openly music matching uses mutual opt-in rather than public likes or swipe mechanics.

- Discovery eligibility is opt-in via `music_preferences.discovery_opt_in`.
- Suggestions are ranked by the existing artist/genre compatibility formula.
- A user's `music_match_interests` row is private and never readable by clients.
- A match is created only after both directional interests exist.
- Once created, a `music_matches` row persists until either participant explicitly removes it.
- Public profile visibility is independent from discovery. Tracks, artists and genres can each be shown or hidden separately.
- Hiding a category from the public profile does not remove it from similarity scoring.
- Blocks, visibility rules and mutes continue to be applied by server-side functions.
