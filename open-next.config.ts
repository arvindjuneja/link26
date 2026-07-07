import { defineCloudflareConfig } from "@opennextjs/cloudflare";

// OpenNext → Cloudflare Workers adapter config. Defaults are fine for this app:
// it's client-heavy (terminal / canvas / three.js) with local persistence, so there's
// no incremental-cache / KV / R2 to wire up yet. When we add server-authoritative
// saves for beta, an R2/D1/KV cache can be configured here.
export default defineCloudflareConfig({});
