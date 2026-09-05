# Build, sign and install from iPhone or iPad

All compilation and signing happen on GitHub's macOS runner. Safari or the GitHub app manages the process. You do not need a personal Mac. GitHub macOS runner availability, quotas and any billing limits apply; Apple Developer membership does not include GitHub runner capacity.

## Workflows

- **Openly native verification** runs on the review PR and can be triggered manually once its workflow is on the repository default branch. It compiles with Xcode 26.3 and runs iPhone/iPad simulator tests without distribution credentials.
- **Openly iPhone and iPad** is manually triggered. `verify` runs validation and simulator tests. `testflight` exports an App Store Connect IPA and optionally uploads it. `ad-hoc` exports a separate IPA limited to registered devices in its provisioning profile.
- **Openly validation** checks TypeScript, ESLint, API tests and the web build.

GitHub requires a workflow_dispatch workflow to exist on the default branch before it can be manually selected. Do not merge this entire platform replacement merely to activate a workflow. First review the implementation/migration, or import the source into a dedicated repository and set its default branch. The existing production application has not been replaced.

## Repository for signed artifacts

The current review repository is public. Simulator checks and the clearly labeled unsigned device compilation artifact may run there. Signed distribution is deliberately refused in a public repository because downloadable IPA artifacts contain provisioning metadata, including device identifiers for Ad Hoc. Use a dedicated private repository for signed builds, or change repository visibility only after considering its existing users and deployments. This is enforced before importing signing assets and again at artifact upload.

You can create the private repository and a Codespace in Safari on iPhone/iPad, import the delivered source there, then commit/push with the Codespace's repository authorization. No personal Mac is involved. Keep the source review branch separate from the existing production deployment. Private macOS runner usage is subject to your GitHub plan and billing limits.

## Public configuration

Create a GitHub Environment named `ios-signing` under repository Settings → Environments. A repository owner can do this in Safari using the desktop site layout. Configure environment variables:

| Variable | Value |
| --- | --- |
| `OPENLY_API_ORIGIN` | The HTTPS origin of this implementation's accessible backend, without a path or query |
| `IOS_BUNDLE_ID` | Your registered explicit Bundle ID; source default is `com.openly.social` |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |
| `ASC_APP_ID` | Numeric App Store Connect application ID, needed to check processing |
| `ENABLE_UNIVERSAL_LINKS` | `true` only after the domain serves the matching association file; otherwise `false` |

The source version is 1.0.0. The workflow's version input sets the marketing version; `github.run_number` sets the build number. If this App Store Connect record already has higher build numbers, update the build-number strategy before uploading. Existing build numbers must not be reused.

The private review Site is owner-gated and is not a general native API host. Do not embed an owner bypass token in the app. Deploy the same Worker/D1/R2 stack to an accessible backend, then use that origin for both website and app. Do not point the new app at the older Supabase application's incompatible API.

## Secure signing assets

Register the Bundle ID with Push Notifications capability. Add Associated Domains only when using universal links. Create the matching app record in App Store Connect. Save the following through **GitHub Environment secrets**, never in chat or source:

| Secret | Contents |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64-encoded Apple Distribution certificate plus its private key, exported as PKCS#12 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password protecting that PKCS#12 file |
| `IOS_APPSTORE_PROFILE_BASE64` | Base64 App Store Connect distribution provisioning profile matching team, certificate and Bundle ID |
| `IOS_ADHOC_PROFILE_BASE64` | Base64 Ad Hoc provisioning profile containing your registered device UDIDs |
| `ASC_PRIVATE_KEY_BASE64` | Base64 App Store Connect API private `.p8` key |
| `ASC_KEY_ID` | That API key's ID |
| `ASC_ISSUER_ID` | Your App Store Connect issuer ID |

The API key must have permission to upload builds and inspect the chosen application. Apple API keys for App Store Connect and APNs are distinct integrations. Do not put an Apple ID password or a two-factor code into the project or conversation.

Without a Mac, signing material can be prepared in a private secure development environment such as a GitHub Codespace: generate the private key and certificate signing request with OpenSSL, upload only the CSR to Apple Certificates, download the issued distribution certificate, and export certificate plus matching private key to a password-protected PKCS#12 file. Keep private keys in the secure workspace and secret store, not in terminal output, repository commits or Actions artifacts. Use Apple Developer's browser portal to register devices and obtain each provisioning profile. A P12 without the matching private key cannot sign a build.

The pipeline imports assets into a temporary keychain, checks profile team/identifier/expiration/push capability/distribution method, archives, exports, verifies with codesign, and cleans up signing material on success or failure. Export methods are `app-store-connect` and `release-testing` respectively. Only deliverable IPAs and their verification reports are uploaded; certificates/private keys are not artifacts.

## Trigger and retrieve

1. Open the repository → Actions → **Openly iPhone and iPad** → Run workflow.
2. Select the reviewed branch, version and method. Begin with `verify`.
3. For TestFlight choose `testflight` and leave upload enabled. For registered-device installation choose `ad-hoc`.
4. Open the run and inspect validation, simulator, archive, export, signature and upload steps independently.
5. Download the artifact under the completed run. Names include version, build and intended method. The ZIP contains a signed IPA and a JSON signature/distribution report when those steps succeeded.

A successful archive is not an exported IPA. A successful signature is not an upload. An accepted upload is not finished Apple processing. `testflight-status.json` records the observed processing state; `VALID` is not a claim that testers have access. Select the processed build in App Store Connect, complete any required compliance metadata and assign tester groups. External testing may require Beta App Review. Public App Store submission is not part of these workflows.

Install TestFlight from the App Store and accept the relevant testing invitation. An App Store Connect IPA is not for arbitrary direct installation. An Ad Hoc IPA installs only on devices included in its profile, through a compatible authorized installation method; simply downloading an IPA in Safari does not install it. Real-device installation must be tested separately.

## References

[GitHub signing on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications), [Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/), [macOS 15 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).

Simulator tests use local ad hoc code signing (`codesign -`) with a simulator-only entitlement file so Keychain tests exercise actual secure storage. This needs no Apple certificate and is distinct from an Apple-signed Ad Hoc distribution IPA for registered physical devices. Device archives always use the distribution profile and production entitlement file.
