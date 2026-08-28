import { defineCloudflareConfig } from '@opennextjs/cloudflare'

export default {
  ...defineCloudflareConfig(),

  // The adapter shells out to the app's build script to produce the Next.js
  // output, defaulting to `npm run build` (see `buildNextjsApp` in
  // @opennextjs/aws). `build` is the command every host runs -- Cloudflare
  // Workers Builds included -- and a plain `next build` leaves it with no
  // .open-next/worker.js to upload, which is exactly how production went
  // undeployed. So `build` produces the Worker, and the adapter is pointed at
  // `build:next` here; without this the script would invoke itself forever.
  buildCommand: 'npm run build:next'
}
