# Openly authentication configuration

Openly uses Supabase Auth as the single authentication authority for web and native iOS.

## Web runtime

Required public variables:

- `NEXT_PUBLIC_SITE_URL`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

Do not add the Supabase service-role key to the web application and do not prefix secrets with `NEXT_PUBLIC_`.

## Email OTP

The Supabase email template must include `{{ .Token }}`. Openly requests passwordless email OTP with `signInWithOtp` and verifies it with `verifyOtp(type: 'email')`.

SMTP is configured outside the repository in Supabase Auth. No SMTP password is stored in Git.

## Phone OTP

Openly sends phone numbers to Supabase in E.164 format and verifies with the SMS OTP type. A supported SMS provider must be configured in Supabase Auth before phone delivery can work.

## Google

Web uses Supabase OAuth/PKCE and the existing server callback. iOS uses the official GoogleSignIn-iOS SDK and submits the Google ID token to Supabase.

iOS build settings required:
- `GOOGLE_IOS_CLIENT_ID`
- `GOOGLE_REVERSED_CLIENT_ID`

The Google web and iOS client IDs must both be registered in the Supabase Google provider configuration.

## Apple

Web uses Supabase OAuth/PKCE. iOS uses AuthenticationServices with a SHA-256 nonce and submits the Apple identity token plus raw nonce to Supabase.

The `ink.openly.app` App ID must have Sign in with Apple enabled. Web OAuth additionally requires an Apple Services ID and a current Apple client secret in the Supabase Apple provider configuration. Never commit the `.p8` key.

## Identity linking

Supabase automatic identity linking is relied on for OAuth identities that have the same verified email. Openly does not perform custom linking based only on a matching email string.

Manual identity linking is intentionally not enabled in application code unless the Supabase project's manual-linking setting is explicitly enabled and the user initiates linking while already authenticated.
