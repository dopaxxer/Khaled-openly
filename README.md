# Openly

A bilingual social product with a responsive React website, a native SwiftUI iPhone/iPad application, and a shared Cloudflare Worker API backed by D1 and private R2 media storage.

This implementation lives on an isolated review branch. It uses a new schema and authentication store. It does not migrate or replace the existing Openly production users or Supabase database. Review the architecture and migration plan before any production cutover.

## Run and verify

Node.js 24.19.0 and npm are used with the committed package-lock.json. No private credentials belong in source.

```sh
npm ci
npm run dev
npm run typecheck
npm run lint
npm test
```

The migration in `drizzle/` defines the database. API integration tests execute the actual request handler against isolated SQLite databases with two or three generated test accounts. They never seed a production account or present test activity in the product.

## Source

- `app/`, `components/openly/`: responsive website, Arabic/English UI, design system and interaction state.
- `server/api.ts`: authentication, authorization, social operations, private media, SSE and APNs integration.
- `db/schema.ts`, `drizzle/`: database schema and migration.
- `ios/`: native SwiftUI app, Xcode project, assets, permissions, unit and UI tests.
- `.github/workflows/`: web/API validation, native verification, manual signing/distribution.
- `scripts/ios/`: deterministic Xcode project generation, signing asset validation, export and verification.

## iPhone and iPad

The app uses SwiftUI, Keychain, PhotosPicker, UIImagePickerController, AVFoundation, URLSession and UserNotifications. It is not a PWA or a WebView wrapper. It requires iOS 17 or later. Xcode is provided by a GitHub macOS runner; a personal Mac is not required.

Run **Openly native verification** for simulator checks. Run **Openly iPhone and iPad** with `verify`, `testflight`, or `ad-hoc` for the corresponding distribution process. Signed distribution requires a publicly reachable API origin and secure Apple signing configuration. An unsigned build is not installable on an arbitrary device.

Detailed handover and secure setup instructions are in `docs/`.
