# Openly handover — verification record

Version: 1.0.0. This record separates implementation from observed verification. The repository review branch is `codex/openly-platform-20260905`, with [review PR #66](https://github.com/dopaxxer/Khaled-openly/pull/66). Existing production code and data have not been replaced.

## Implemented

The website and SwiftUI clients cover registration, profile setup, posting, discovery, following/requests, private messaging/requests, collections, Circles/moderation, Moments, notifications and privacy settings. They share the Worker API, D1 schema and private R2 storage. Music uses real Apple catalog metadata/previews. UI languages are Arabic and English, with directional layouts and light/dark/system appearance. There are no seeded production people, conversations or engagement.

The server checks identity and permissions on protected reads and writes. Post/message retry IDs are stable. Message state comes from actual writes and recipient acknowledgements. Moment and media expiry are enforced by server time. Build and signing workflows, environment examples, app assets and separate TestFlight/Ad Hoc export paths are included.

## Automatically verified locally

- TypeScript type-check: passed.
- ESLint: passed.
- Production web/Worker build: passed.
- Full Node suite: **22 passed, 0 failed** (17 API integration tests and 5 rendering/component checks).
- Workflow YAML, application plist parsing and Python/shell/JavaScript build-script syntax checks: passed.
- Additional provisioning/export validation suite: **12 passed**. Synthetic metadata checks expired or mismatched profiles, distribution methods, allowed certificates/entitlements, exported version/build and universal-link domains. These fixtures cannot sign an app and do not prove Apple acceptance. The suite is a required validation step before distribution.

API tests execute the actual server handler using SQLite with the real SQL migrations, and an isolated R2-compatible storage test double. Two generated accounts are used throughout; a third account checks conversation isolation. These are database/API integration tests, not a claim of full device UI end-to-end coverage or a production R2 load test.

Coverage includes the register → profile → publish → discover → follow → permitted conversation → reply journey; private follow acceptance; own-only audience; collection isolation; actual delivered/read acknowledgements and receipt opt-out; retries; blocking across surfaces; private Circle moderation; post and media expiration; account deletion/media cleanup; ranked pagination and pins; recovery/session revocation; deleted notification targets; isolated drafts/settings; actual SSE updates/reconnect; upload validation and interrupted streams.

## Automatically verified in the cloud

[Web/API validation](https://github.com/dopaxxer/Khaled-openly/actions/runs/33943092695) completed successfully on GitHub Ubuntu, using a clean locked dependency installation, TypeScript, ESLint, API tests and the production build.

[Native verification](https://github.com/dopaxxer/Khaled-openly/actions/runs/33942365485) completed successfully on GitHub macOS with Xcode 26.3: the native app compiled for the simulator and in Release for the physical-device SDK without distribution signing; 3 unit tests and 2 UI tests passed on iPhone; the 2 UI tests also passed on iPad. These tests verify Keychain persistence/deletion, Arabic draft serialization, unknown receipt handling, Arabic registration UI and English keyboard dismissal. They do not exercise authenticated social journeys or real-device permissions. The run generated an unsigned app compilation artifact, not an installable IPA. Subsequent source revisions use the same PR checks; see the PR Checks view for the latest run.

## Deployment

The [private review website](https://openly.dersier.chatgpt.site) was successfully published with the Worker and D1/R2 bindings. This is an owner-private review deployment, not the public backend needed by distributed native clients. No App Store or TestFlight deployment was made.

## Manually inspected

The desktop authentication/onboarding entry surface was inspected in the browser in Arabic and English, including RTL/LTR, labels, typography and language switching. The authenticated web journey was not manually completed. Further direct API navigation in the browser environment was blocked; no production Site URL was opened to substitute for that check.

## Required device and acceptance checks

No physical iPhone or iPad was available. Installation, camera/photo/microphone permission behavior, push delivery, interrupted cellular uploads, background/foreground reconnects and full authenticated journeys have not been verified on physical hardware.

The following remain manual acceptance gates: all authenticated screens in light/dark and Arabic/English; narrow phone layouts; iPad multitasking; accessibility text sizes/VoiceOver; keyboard-open sheets/navigation; restoration after long feed/chat browsing; weak connectivity and large media; moderation operations with real authorized moderators; and full two-account journeys against the final public backend.

## Distribution blockers

The current review repository is public; signed artifacts require a private distribution repository. No Apple distribution certificate/private key, matching provisioning profiles or App Store Connect API key were available to execute signing in this session. A publicly reachable compatible backend origin and confirmed app/team configuration are also needed for a distributed native build. Ad Hoc additionally requires registered device identifiers in its profile.

No signed IPA has been generated. No TestFlight upload, Apple processing completion, tester availability or physical-device installation is claimed. The manual workflows must be made available on the chosen repository's default branch through a reviewed integration or a dedicated repository. The existing production application uses a different account store; migrating it is a separate required decision before cutover.

See `IOS-DISTRIBUTION.md` for the exact secret names and phone/tablet workflow; see `WEB-DEPLOYMENT.md` for the public backend setup. Email verification/email recovery, web push, production capacity testing, retention sweeps and an independent security/accessibility review are not represented as completed.
