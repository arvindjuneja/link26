export const meta = {
  name: 'link26-rethink',
  description: 'Design a full game-design + technical proposal to evolve Link26 into a viable, cybersec-credible hacking sim across web + iOS',
  phases: [
    { title: 'Pillars', detail: 'parallel design across 6 dimensions' },
    { title: 'Synthesize', detail: 'unify into one coherent vision + roadmap' },
    { title: 'Critique', detail: 'adversarial: credibility, fun, cost-reality' },
    { title: 'Finalize', detail: 'fold critique into the final design doc' },
  ],
}

const CONTEXT = `
PROJECT: "Link26" — a browser hacking-sim, sentimental homage to Introversion's UPLINK (2001), set in 2026.

CURRENT STATE (what already exists, must build on it, not ignore it):
- Stack: Next.js 16 (App Router), React 19, Zustand state + IndexedDB local save, Supabase (auth + Postgres cloud save, in progress), Three.js (react-three-fiber) VFX overlay, Canvas2D world map, Tailwind 4, Web Audio API synthesized sounds.
- Core loop today: terminal command line. scan <host> -> build a proxy route (each proxy has heat/anonymity/cost, burns out with overuse) -> connect <host> -> ls/cat/cp/rm/edit remote files -> submit mission for cash + reputation.
- "Narrative trace" system instead of a raw % bar: states CALM -> ALERT -> HUNT -> LOCKDOWN. Trace decays while disconnected, spikes on direct connect / unscanned connect / log wiping. This is the emotional heartbeat (mirrors Uplink's Trace Tracker).
- World map (Canvas2D) plots real cities for hosts + proxies, animates scan waves / data packets along the route.
- CONTENT IS THIN: only 10 static hosts, 15 proxies, exactly 3 hardcoded missions. No LLM integration. None of the OSINT / wardriving / drone-EW / camera-snooping / ELINT pillars exist yet.

OWNER VISION (verbatim intent): "Rethink the whole thing." Make it a viable game hostable on Firebase / Cloudflare Pages. Strongly leaning toward also shipping an iOS game. Wants it "full of cool scenarios and options." Wants the EMOTIONS Uplink produced. Modern. Missions that USE LLMs, drone warfare / EW, snooping open cameras to spot things, OSINT, wardriving, cyber warfare, ELINT, red teaming. "No gimmicks — this is already watched by the cybersec community." Frame: an ARCADE SIMULATOR of red teaming / OSINT / hacking / wardriving / cyber warfare / ELINT.

HARD GUARDRAIL (apply everywhere): This is an ARCADE SIMULATOR — evocative and conceptually credible, NEVER an operational how-to. Use real tradecraft VOCABULARY and workflow shape (the names of phases, tools, concepts a practitioner would recognize) to earn cybersec respect, but abstract all mechanics into game systems. No working payloads, exploit code, real exploitation steps, real target data, or instructions that transfer to reality. Credibility comes from authentic terminology, accurate mental models, and respect for the craft — not from real attack instructions.

RESEARCH ALREADY GATHERED (fold in, don't re-derive):
- WHY UPLINK HIT: it felt like a TOOLKIT not a game (desktop-as-OS immersion); the Trace Tracker beeped like a heart-rate monitor as the window closed; melancholy blue palette + minimal ambient synth = "calculated expert + cyberpunk isolation"; the core emotional engine is the BALANCE of power (owning a hardened mainframe feels superhuman) and vulnerability (you never stop looking over your shoulder). Gameplay was arguably monotonous but immersion/tension redeemed it.
- MODERN PEERS: Hacknet (terminal realism + narrative rabbit-hole, ~9.2/10), Bitburner (programmer-deep idle/incremental, real scripting), Grey Hack (MMO, procedural networks, full freedom). Lessons: terminal authenticity sells; a narrative spine matters; procedural generation gives longevity; deep systems retain the hardcore but must not wall out newcomers.
- HOSTING: Cloudflare now recommends OpenNext (@opennextjs/cloudflare) on Cloudflare Workers for Next.js SSR; @cloudflare/next-on-pages is deprecated; static export works great on Pages. CF gives unlimited bandwidth + 300+ edge locations. Firebase Hosting is weak on modern App Router SSR / RSC / server actions and its function billing gets unpredictable under SSR load. Supabase already chosen for auth + Postgres.
- iOS: Capacitor wraps a Next.js/PWA build into a native iOS (and Android) shell from ONE codebase, with access to camera/filesystem/push; no rewrite. PWA alone is weaker on iOS (push, background sync).
`

const PILLAR_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'thesis', 'content_markdown', 'key_decisions', 'risks', 'reuses_existing'],
  properties: {
    title: { type: 'string', description: 'Pillar name' },
    thesis: { type: 'string', description: '1-2 sentence core argument for this pillar' },
    content_markdown: { type: 'string', description: 'Detailed design content as rich markdown. Be concrete and specific. Use headings, tables, examples. This is the substance.' },
    key_decisions: { type: 'array', items: { type: 'string' }, description: 'Decisions this pillar makes or forces, phrased as resolved choices with rationale' },
    risks: { type: 'array', items: { type: 'string' }, description: 'Risks, unknowns, or things that could go wrong' },
    reuses_existing: { type: 'string', description: 'Exactly how this builds on the EXISTING Link26 code/systems rather than replacing them' },
  },
}

const PILLARS = [
  {
    key: 'feel',
    label: 'feel:emotional-core',
    prompt: `You design the EMOTIONAL CORE & GAME FEEL.
Define the single coherent player fantasy that unifies all 5 domains (red teaming, OSINT, wardriving, drone/EW, ELINT/SIGINT, camera-snooping) into ONE believable character — who is the player, what is their arc, why do they care. Define the central minute-to-minute loop and the session shape (a "job" arc). Re-architect the trace/heartbeat tension for the expanded scope (multiple detection vectors: network trace, physical/RF exposure, OSINT footprint, attribution). Specify the power<->vulnerability balance moments. Define how a mission STARTS and ENDS emotionally. Define difficulty/accessibility (newcomer vs cybersec pro) without dumbing down. Name 3-5 "signature moments" the game must deliver that players will talk about. Propose a working game NAME and one-line positioning (Link26 may stay or evolve).`,
  },
  {
    key: 'missions',
    label: 'missions:scenarios',
    prompt: `You design MISSIONS & SCENARIOS — the heart of "full of cool scenarios."
Produce a CATALOG of at least 14 concrete, distinct missions spanning every pillar: classic red-team network ops, OSINT investigations (identify a person/asset from breadcrumbs), wardriving (map/own wireless infra in an area), drone & electronic warfare (counter-UAS, GPS-spoof/jam scenarios as game abstractions), ELINT/SIGINT (intercept & classify signals), and snooping exposed/open cameras to spot a thing/person/event. For EACH mission give: title, the hook (briefing voice), the fantasy, step-by-step player-facing beats (abstracted, no real how-to), which tools/screens it uses, the detection/risk vectors, branching/failure states, and reward. THEN design the LLM-POWERED MISSION ENGINE: how a large language model (recommend Anthropic Claude tiers) generates dynamic targets, drives NPC dialogue & social-engineering conversations, runs an in-world "analyst/handler", grades open-ended OSINT answers, and produces near-infinite procedural contracts — with cost/abuse controls. Include 2-3 multi-mission narrative arcs (campaign spine) and the idea of factions/clients with conflicting agendas.`,
  },
  {
    key: 'systems',
    label: 'systems:world-progression',
    prompt: `You design WORLD, SYSTEMS & PROGRESSION.
Design: the procedural world generator (how LLM + rules spawn hosts, people, networks, RF environments, camera feeds, drones) so the game has longevity beyond 10 static hosts; the gear/hardware economy (CPU/RAM/bandwidth/modems/SDR/antenna/drone-jammers as upgradeable gear, evolving the existing tools), a skill/perk tree across the disciplines, the proxy/anonymity economy (extend the existing heat/anonymity/cost model to RF & physical exposure), reputation & multiple factions, the cash economy & sinks, meta-progression and prestige, and the SAVE/STATE model (evolve the current Zustand+IndexedDB+Supabase shape — what must be authoritative server-side to prevent cheating, what stays local, how seasons/leaderboards work). Define the "where is what" information architecture at the systems level: what persistent subsystems exist.`,
  },
  {
    key: 'uiux',
    label: 'uiux:art-sound',
    prompt: `You design UI/UX, ART DIRECTION & SOUND — the "rethink how it looks and feels" + "where is what".
Re-architect the screen. Today it's terminal + Canvas2D world map + 3D VFX overlay. Design the full desktop/OS metaphor (Uplink's gateway desktop, modernized): the windows/apps the player runs (terminal, world map, OSINT graph board, RF/SDR waterfall, camera grid viewer, drone tactical map, mission inbox, gear shop, faction comms), how they're arranged, and how the player moves between them. Define a precise VISUAL IDENTITY (palette extending the melancholy blue, typography, grid, motion language, glitch/scanline budget — tasteful not gimmicky) and a SOUND design brief (ambient bed, the trace heartbeat, UI cues). CRUCIAL: design the MOBILE/TOUCH adaptation for iOS — how a terminal+multi-window desktop game becomes great on a phone/tablet (command palette vs typing, gesture nav, panel system, portrait vs landscape). Give an ASCII wireframe of the desktop layout and the mobile layout.`,
  },
  {
    key: 'tech',
    label: 'tech:architecture',
    prompt: `You design the TECHNICAL ARCHITECTURE for shipping this as a viable product on web + iOS. You are an LLM-app + web architect.
Decide and justify: hosting (reconcile the owner's "Firebase/Cloudflare Pages" instinct with the research — recommend a concrete stack; Cloudflare Workers + OpenNext vs Cloudflare Pages static export vs Firebase, given existing Supabase auth/Postgres); where the IN-GAME LLM CALLS run (must protect API keys -> server/edge function or Worker; recommend Anthropic Claude model tiers per use-case: cheap model for NPC chatter/flavor, mid for grading/procedural gen, top for marquee campaign beats — name current model ids and reasoning) and how to control cost/abuse (rate limits, token budgets per player, caching, server-authoritative validation, free-tier vs paid LLM access). Design the data model & server-authoritative anti-cheat boundary. Design iOS via Capacitor (build pipeline, what needs static export vs server calls, offline play, App Store review considerations for a "hacking" game). Give a migration path from the CURRENT codebase (incremental, what to refactor first). Address: does turning the LLM-dependent game offline-capable even work? Estimate rough monthly cost envelopes at 1k and 50k MAU.`,
  },
  {
    key: 'cred',
    label: 'cred:ethics-biz-community',
    prompt: `You design CYBERSEC CREDIBILITY, ETHICS, MONETIZATION & COMMUNITY.
The owner says the cybersec community is already watching and wants "no gimmicks." Define exactly how this game earns and keeps practitioner respect: authentic terminology/workflows, nods to real frameworks (MITRE ATT&CK phases, the OSINT lifecycle, the recon->weaponize->... kill-chain shape) used as GAME STRUCTURE, optional "how it really works" codex entries, CTF-style challenges, possible community/creator partnerships. Draw the RESPONSIBLE-DESIGN line precisely: what the game depicts vs never depicts (the arcade-not-how-to boundary), how to handle the camera-snooping/drone/EW pillars tastefully and legally, age rating implications. Design MONETIZATION that won't alienate this audience (premium one-time? cosmetic? season pass? explicitly reject pay-to-win / scummy F2P) for both web and iOS (App Store cut). Design COMMUNITY & RETENTION: leaderboards, seasons, daily contracts, user-generated/shared missions, an agent-ranking ladder (the existing roadmap mentions this), spectating, and how LLM enables endless content. Address legal/ToS, and a marketing wedge to launch with the cybersec crowd.`,
  },
]

phase('Pillars')
const pillars = await parallel(
  PILLARS.map((p) => () =>
    agent(`${CONTEXT}\n\n--- YOUR ASSIGNMENT ---\n${p.prompt}\n\nReturn rich, concrete, opinionated design. Make decisions; don't hedge. Specificity and authenticity over breadth-without-depth.`,
      { label: p.label, phase: 'Pillars', schema: PILLAR_SCHEMA })
      .then((r) => (r ? { ...r, key: p.key } : null))
  )
)
const goodPillars = pillars.filter(Boolean)
log(`Pillars complete: ${goodPillars.length}/${PILLARS.length}`)

const pillarDigest = goodPillars.map((p) =>
  `### PILLAR: ${p.title}\nTHESIS: ${p.thesis}\nKEY DECISIONS:\n- ${(p.key_decisions||[]).join('\n- ')}\nRISKS:\n- ${(p.risks||[]).join('\n- ')}\nBUILDS ON EXISTING: ${p.reuses_existing}\n\nDETAIL:\n${p.content_markdown}`
).join('\n\n========================================\n\n')

phase('Synthesize')
const SYNTH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['game_name', 'positioning', 'elevator_pitch', 'core_loop_markdown', 'unified_vision_markdown', 'mvp_scope', 'full_vision_scope', 'roadmap_phases', 'conflicts_resolved', 'open_decisions'],
  properties: {
    game_name: { type: 'string', description: 'Recommended product name (keep Link26 or evolve), with 1-line rationale' },
    positioning: { type: 'string', description: 'One-sentence positioning / tagline' },
    elevator_pitch: { type: 'string', description: '3-4 sentence pitch a publisher or the cybersec crowd would repeat' },
    core_loop_markdown: { type: 'string', description: 'The unified core gameplay loop, concrete, as markdown' },
    unified_vision_markdown: { type: 'string', description: 'The cohesive vision weaving all six pillars into one game. The centerpiece narrative of the design. Rich markdown.' },
    mvp_scope: { type: 'array', items: { type: 'string' }, description: 'The v1 / first shippable slice — what is IN, ruthlessly scoped' },
    full_vision_scope: { type: 'array', items: { type: 'string' }, description: 'The eventual full feature set beyond v1' },
    roadmap_phases: {
      type: 'array',
      description: 'Ordered delivery phases from current code to full vision',
      items: {
        type: 'object', additionalProperties: false,
        required: ['phase', 'goal', 'deliverables', 'rough_effort'],
        properties: {
          phase: { type: 'string' }, goal: { type: 'string' },
          deliverables: { type: 'array', items: { type: 'string' } },
          rough_effort: { type: 'string', description: 'rough size, e.g. weekend / 1-2 wks / 1 mo' },
        },
      },
    },
    conflicts_resolved: { type: 'array', items: { type: 'string' }, description: 'Tensions between pillars and how you resolved them' },
    open_decisions: {
      type: 'array',
      description: 'The few decisions that are genuinely the OWNER\'s to make (not derivable). Each with options + your recommendation.',
      items: {
        type: 'object', additionalProperties: false,
        required: ['question', 'options', 'recommendation'],
        properties: {
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          recommendation: { type: 'string' },
        },
      },
    },
  },
}
const synthesis = await agent(
  `${CONTEXT}\n\nSix design pillars were produced in parallel. Synthesize them into ONE coherent, cohesive game vision. Resolve conflicts between pillars decisively. Keep the Uplink emotional core central. Be ambitious but ground the roadmap in the EXISTING codebase as the starting point. The MVP must be ruthlessly scoped and genuinely shippable; the full vision can be grand.\n\n=== PILLAR OUTPUTS ===\n${pillarDigest}`,
  { label: 'synthesize', phase: 'Synthesize', schema: SYNTH_SCHEMA }
)

phase('Critique')
const CRITIQUE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['lens', 'verdict', 'strengths', 'weaknesses', 'must_fix', 'specific_additions'],
  properties: {
    lens: { type: 'string' },
    verdict: { type: 'string', enum: ['ship-worthy', 'promising-needs-work', 'fundamental-problems'] },
    strengths: { type: 'array', items: { type: 'string' } },
    weaknesses: { type: 'array', items: { type: 'string' } },
    must_fix: { type: 'array', items: { type: 'string' }, description: 'Concrete things the final doc must change/add' },
    specific_additions: { type: 'array', items: { type: 'string' }, description: 'Concrete ideas/scenarios/mechanics worth adding that synthesis missed' },
  },
}
const synthDigest = JSON.stringify(synthesis, null, 2)
const LENSES = [
  { key: 'credibility', prompt: `You are a respected red-teamer / OSINT practitioner who is SKEPTICAL of "hacker games." Judge whether this design earns cybersec-community respect or reads as Hollywood cringe. Attack any inauthenticity. Check the responsible-design line is real and defensible. Reward authentic tradecraft framing. Suggest specific authentic details that would make practitioners nod.` },
  { key: 'fun-retention', prompt: `You are a senior game designer (systems + F2P/premium retention). Judge whether this is actually FUN minute-to-minute and whether it retains players past day 1 and week 1. Attack tedium, unclear feedback loops, grind, and any "spreadsheet not a game" risk. Verify the Uplink TENSION actually survives. Check the LLM doesn't make missions feel mushy/ungradeable. Suggest concrete fun/retention mechanics.` },
  { key: 'cost-shipping-reality', prompt: `You are a pragmatic technical founder shipping a solo/small-team indie game on a budget. Attack scope creep, LLM cost blowups, offline/iOS-review landmines, and anything that can't realistically ship. Pressure-test the hosting/cost estimates and the MVP scope. Verify the migration path from the current Next.js/Zustand/Supabase code is real and incremental. Flag the riskiest assumption.` },
]
const critiques = await parallel(
  LENSES.map((l) => () =>
    agent(`${CONTEXT}\n\nHere is the synthesized game vision to critique through your lens:\n\n${synthDigest}\n\n--- YOUR LENS ---\n${l.prompt}\n\nBe specific and adversarial but constructive. Your must_fix items will be folded into the final design.`,
      { label: `critique:${l.key}`, phase: 'Critique', schema: CRITIQUE_SCHEMA })
  )
).then((rs) => rs.filter(Boolean))

phase('Finalize')
const FINAL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['design_doc_markdown', 'chat_summary_markdown', 'top_open_decisions'],
  properties: {
    design_doc_markdown: { type: 'string', description: 'The COMPLETE, polished, standalone game design + technical proposal as a long markdown document. This will be saved to disk as the canonical design doc. Include all sections: vision/positioning, the player & fantasy, core loop, the six pillars (feel, missions+LLM engine, world/systems/progression, UI/UX/art/sound, technical architecture incl. hosting+LLM+iOS+costs, credibility/ethics/monetization/community), MVP scope, full vision, and a phased roadmap from the current codebase. Fold in the critique must-fixes. Use headings, tables, mission examples, ASCII wireframes, cost tables. Be the definitive document.' },
    chat_summary_markdown: { type: 'string', description: 'A punchy, exciting but honest summary to show the owner in chat (~400-600 words): the big idea, what changes, the standout scenarios, the tech recommendation, and what the MVP is. Energetic, not corporate.' },
    top_open_decisions: {
      type: 'array', description: 'The 3-4 decisions that are genuinely the owner\'s to make now',
      items: { type: 'object', additionalProperties: false, required: ['header', 'question', 'options', 'recommendation'],
        properties: {
          header: { type: 'string', description: 'short <=12 char label' },
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
          recommendation: { type: 'string' },
        } },
    },
  },
}
const critiqueDigest = critiques.map((c) =>
  `LENS ${c.lens} — verdict ${c.verdict}\nMUST FIX:\n- ${(c.must_fix||[]).join('\n- ')}\nADD:\n- ${(c.specific_additions||[]).join('\n- ')}\nWEAKNESSES:\n- ${(c.weaknesses||[]).join('\n- ')}`
).join('\n\n')

const final = await agent(
  `${CONTEXT}\n\nProduce the DEFINITIVE design document. You have (A) the synthesized vision and (B) adversarial critiques from three lenses. Fold every credible must-fix into the final document; where critiques conflict, decide and note why. Keep the Uplink emotional core sacred. Make the doc genuinely useful to build from.\n\n=== SYNTHESIZED VISION ===\n${synthDigest}\n\n=== CRITIQUES ===\n${critiqueDigest}\n\n=== ALSO AVAILABLE: full pillar detail (for depth) ===\n${pillarDigest}`,
  { label: 'finalize', phase: 'Finalize', schema: FINAL_SCHEMA, effort: 'high' }
)

return { final, synthesis, critiques, pillarTitles: goodPillars.map((p) => p.title) }
