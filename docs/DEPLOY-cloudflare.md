# Deploy to Cloudflare (a tester URL)

The app runs on **Cloudflare Workers** via `@opennextjs/cloudflare`. This gets a public,
obscure URL you can hand to testers. No backend, no accounts, no secrets required — the
game saves locally in each tester's browser and ships with baked content.

## One-time
1. A free **Cloudflare account** (dash.cloudflare.com).
2. Log in the CLI (interactive — run it yourself so the browser OAuth works):
   ```
   ! npx wrangler login
   ```

## Deploy (and re-deploy)
```
npm run deploy
```
This runs `opennextjs-cloudflare build && opennextjs-cloudflare deploy`. The **first**
deploy may ask you to register a free `*.workers.dev` subdomain — accept it. When it
finishes it prints the URL:
```
https://link26.<your-subdomain>.workers.dev
```
Share that link with testers. To push a new build later, just run `npm run deploy` again.

## Verify it locally first (optional)
Run the exact Worker bundle in Cloudflare's local runtime (no login needed):
```
npm run preview          # build + serve in workerd
# or, against an existing build:  npx wrangler dev
```
Then open http://localhost:8787 (`/` = red seat, `/soc` = blue seat).

## Optional: live LLM content
Without a key the game uses its baked content pack (fully playable). To enable live
Anthropic-generated content for the handler/flavor:
```
npx wrangler secret put ANTHROPIC_API_KEY
```

## What testers get / don't get
- **Playable immediately** — both seats, the career hub, all shifts, local save.
- **Saves are per-browser** (IndexedDB + localStorage). Each tester's progress lives on
  their device; clearing site data resets it. You won't see their progress (that needs the
  later Supabase/analytics phase).
- **Not yet hardened** — the economy is client-side (a tester *could* edit their cash in
  devtools). Irrelevant for gathering opinions; the server-authoritative pass is the
  separate "real beta" step (see GAME_DESIGN §9 + the cheat-hole note).

## Config that makes this work (already in the repo)
- `wrangler.jsonc` — Worker name (`link26`), `nodejs_compat`, assets binding.
- `open-next.config.ts` — the OpenNext→Cloudflare adapter config (defaults).
- `next.config.ts` — no `output: "standalone"` (OpenNext builds its own Worker bundle).
- `package.json` — `deploy` / `preview` / `cf-typegen` scripts.
- Next was bumped to **16.2.10** (the adapter requires `>=16.2.6`; 16.1.1 was in an
  unsupported gap).

## Take it down / rename
- Rename: change `name` in `wrangler.jsonc`, re-deploy.
- Remove: `npx wrangler delete`.
