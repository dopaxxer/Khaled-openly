import { defineCloudflareConfig } from '@opennextjs/cloudflare'

// Nothing to override. The app is entirely dynamic -- no ISR, no `use cache`,
// no next/image -- so the default in-Worker behaviour is the whole story and an
// incremental cache would have nothing to store.
export default defineCloudflareConfig()
