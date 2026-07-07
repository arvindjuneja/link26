import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Deployed to Cloudflare Workers via @opennextjs/cloudflare (see open-next.config.ts
  // + wrangler.jsonc). OpenNext transforms the standard Next build into a Worker, so
  // no `output: "standalone"` here.
};

export default nextConfig;
