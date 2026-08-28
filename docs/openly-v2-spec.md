# Openly V2 — Product UI Specification

Status: working design source for `design/openly-v2-editorial`.

## Product invariant

Openly is a calm public space for writing, cultural taste, and conversation. The UI should feel like a place to read and think, not a dashboard and not a clone of a mainstream social feed.

Backend invariants stay untouched by this redesign:
- Existing Supabase data and authentication are source of truth.
- Existing API contracts stay compatible.
- Production data is never reset for visual work.
- Web and native iOS share the same accounts and content.

## Visual direction

Primary direction: **Quiet Editorial**.

Core traits:
- Warm paper canvas.
- Dark ink typography.
- Burgundy/crimson as the default accent.
- Content before chrome.
- Cards only where containment is useful.
- Media is contextual, never dominant.
- Identity is subtle and code-first.
- Motion confirms an action; it does not decorate the screen.

### Foundation colors

Light:
- Canvas: `#f7f4ee`
- Surface: `#fffdf8`
- Soft surface: `#f4efe7`
- Ink: `#171513`
- Muted: `#6b625b`
- Divider: `#e9e1d8`
- Accent: `#7a2035`

Dark:
- Canvas: warm near-black, never pure black.
- Surface: slightly lifted warm charcoal.
- Text: warm off-white.
- Accent remains the user's selected color theme.

## Core mobile navigation

The mobile experience must feel native and immediate:
- Bottom navigation floats above the safe area.
- Active state is quiet and color-led.
- Account identity chip stays visible without becoming an avatar-centric system.
- Notifications/messages remain reachable without crowding the main feed.

## Home

- Header: Openly brand + identity context.
- Public feed is chronological.
- Composer appears before the timeline.
- Composer should open without a layout jump.
- Text is the dominant object.
- Media attachments sit inline and compactly.
- No ranking language or algorithmic discovery in the timeline.

## Profile

- Code and identity color are primary identity.
- Bio/status are editorial text, not profile-card chrome.
- Taste (music/books/films/interests) is integrated as context.
- Followers/following should not dominate hierarchy.
- Actions are compact secondary controls.

## Explore/Search

Search can cover:
- People
- Posts
- Music
- Books
- Films

Discovery by taste:
- Uses overlap in cultural signals.
- Never ranks by follower count.
- Shows why a person is relevant (shared signals).

## Composer

- Writing comes first.
- Media is optional context.
- Supported contextual attachment families:
  - Music
  - Books
  - Films
- Mentions use `@` and should not create notification spam.
- Draft state must survive navigation on iOS.

## Interaction rules

### Like / Save
- Optimistic update immediately.
- No blocking spinner for ordinary interactions.
- If the request fails, revert subtly and preserve context.

### Navigation
- iOS uses native `NavigationStack`/native navigation behavior.
- Interactive edge-swipe back must work.
- Bottom sheets drag interactively.
- Long press opens native-feeling context menus.

### Network
- Slow requests must not freeze the interface.
- Offline drafts stay available.
- Sync resumes automatically when possible.
- Error messages should be local to the failed action.

## Native iOS requirements

The native app is not a website wrapper.

Required behaviors:
- SwiftUI-native navigation.
- Interactive keyboard dismissal in writing/search surfaces.
- Composer remains visible above the keyboard.
- Native haptics for committed interactions where appropriate.
- Image/media loading should be lazy and cached.
- Feed shell should remain stable while data refreshes.
- Swipe-back should preserve the previous view visually during the gesture.

## Screen map

1. Home
2. Profile
3. Explore
4. Post Detail
5. Composer
6. Notifications
7. Login
8. OTP Verification
9. Search
10. Music
11. Books
12. Films
13. Settings
14. Themes
15. Onboarding
16. Mentions
17. Bookmarks
18. Followers + Following
19. User Discovery by Taste
20. Empty + Error + Loading
21. Sheets + Menus
22. iOS Native Specs
23. Auth System
24. Desktop + Design System
25. Media System
26. Interaction States
27. Prototype Flows

Additional pages should cover native/tablet/desktop variants, accessibility, RTL/LTR, privacy/safety, admin/reporting, offline/recovery, and media-detail states.

## Implementation strategy

1. Keep the redesign in `design/openly-v2-editorial`.
2. Add visual changes in isolated layers where possible.
3. Do not change data models for purely visual reasons.
4. Verify web unit tests + Cloudflare build.
5. Verify Swift tests + IPA build.
6. Only merge after visual review and CI success.
