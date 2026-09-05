# Website and backend deployment

The review Site uses managed D1/R2 bindings defined in `.openai/hosting.json`. Its deployment archive includes compiled client/server output and ordered database migrations. Source must be committed and pushed before a version is saved. The review publication remains private to its owner.

To deploy the same implementation for real shared web/native access, use a separate Cloudflare Worker with D1 and a private R2 bucket. A Cloudflare account with those services and sufficient capacity is required. This project does not assume access to your existing Cloudflare account. Do not alter the older application's production Worker or database during setup.

1. Create a new D1 database and R2 bucket. Keep the bucket private and leave public R2 access disabled.
2. Configure a deployment token restricted to the relevant Cloudflare account and required Workers, D1 and R2 actions. Store it as a GitHub Environment secret or your secure CLI environment. Never commit it.
3. Use Node 24.19.0, run `npm ci`, `npm run typecheck`, `npm run lint` and `npm test`.
4. Set public environment values `CLOUDFLARE_WORKER_NAME`, `CLOUDFLARE_D1_ID`, `CLOUDFLARE_R2_BUCKET`, `PUBLIC_ORIGIN`, `IOS_BUNDLE_ID` and `APPLE_TEAM_ID`. Use a new Worker name to avoid replacing existing production.
5. Run `node scripts/prepare-cloudflare.mjs` after the build. This changes only generated `dist/server/wrangler.json`, binding the compiled application to the explicit resources.
6. Apply migrations using `npx wrangler d1 migrations apply DB --remote --config dist/server/wrangler.json`, then deploy using `npx wrangler deploy --config dist/server/wrangler.json`.
7. Configure the HTTPS custom domain corresponding to `PUBLIC_ORIGIN`. Set the native `OPENLY_API_ORIGIN` to this same origin.

The build output is `dist/client` plus `dist/server/index.js`. Do not publish only the client files: the product requires its Worker, D1 and R2 services. Do not use the placeholder local D1 ID for a real deployment. Database changes should be reviewed and backed up before applying to any database containing real users.

For APNs, configure `APNS_PRIVATE_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` and `IOS_BUNDLE_ID` as server runtime secrets/configuration using `wrangler secret put` or the Cloudflare dashboard. Use the production APNs endpoint for TestFlight and Ad Hoc; sandbox mode is for development profiles only. APNs delivery requires a signed device build and permission. No web push service is implemented. In-app notifications work independently of push.

For universal links, set `APPLE_TEAM_ID` and `IOS_BUNDLE_ID` on the backend. The Worker serves `/.well-known/apple-app-site-association`. Enable the native entitlement only after this is reachable over the app domain without authentication. The custom `openly://post/<id>`, `openly://profile/<id>` and `openly://conversation/<id>` schemes are also handled. Every destination rechecks permissions.

Authentication uses email/password plus a private recovery code. SMTP is not required for that recovery flow. Email verification and email-delivered recovery are not implemented; do not configure a fictitious SMTP integration or imply that email ownership has been verified.

Backups, database restore testing, abandoned-upload cleanup, expired-media physical deletion, operational report handling, monitoring and capacity planning remain deployment responsibilities. Media expiration and content privacy are enforced even before cleanup. Monitor SSE connection/database usage; the current implementation targets initial usage and has not been load-tested at consumer-network scale.

The same sequence is automated in **Openly web deployment**. In GitHub create Environment `web-production`, store `CLOUDFLARE_API_TOKEN` as a secret and the explicit account/resource/origin values as variables, including `CLOUDFLARE_ACCOUNT_ID`. Once the reviewed workflow is on the default branch, open Actions → Openly web deployment → Run workflow from Safari. It has no automatic push deployment trigger.
