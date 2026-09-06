# Feel-pass evidence — `docs/ios/FEEL.md`

Motion cannot be judged from a still, so every sequence in `FEEL.md` is recorded on
the simulator and cut into a **100 ms frame grid**. Read `strip.png` first — the whole
sequence, six frames to a row, left to right — and open the individual `f-NNN.png`
when a beat needs a closer look. `manifest.txt` in each directory says which device,
which QA screen, and how the capture ran.

**The fuchsia numerals** in a frame are the running sequence's own elapsed
milliseconds (`RootView.sequenceClock`, `#if SENTRY_QA` — Debug only, and check 3 of
`ios/scripts/verify.sh` proves it is absent from Release). A 100 ms grid on its own
cannot settle §11's ±60 ms tolerance; the clock can, because the beat and the time it
landed at are in the same frame. Every timing claim in `FEEL.md` §14.4 is read off
those numerals.

| Directory | What it shows |
|---|---|
| `handover/` | §1 — the 08:00 handover: typed eyebrow, the rail filling one alert per 260 ms, Vale's card, the dock last. |
| `arrival/` | §2 — an alert arriving: the trigger typed at 260, the title at 1100, the severity chip stamped at 1500, the sources risen at 1800. |
| `pull/` | §4 — a 10-minute pull: the seeded log pane, the shift clock counting 0m → 10m in sync, `RESULTS`, the card. |
| `call/` | §8 — a **good** call: black, the stamp at 450, the ground at 900, the truth flip at 1200, the meters at 1500, `WHY` at 2100, the dock last. No breach beat, so no rose edge. |
| `breach/` | §8's thud arm — a missed detection: the same cut with `.breach` at 1500, one rose edge flash, and §5's fear caption typing itself in as the meter moves for the first time. |
| `states/` | End states, one screen each: §1 · §2 · §3's peek and spent row · §4's query and results · §5's board, live reveal and fear caption · §6's cards · §7's nudge · the 16:00 summary of a full Shift 1. |
| `smoke/` | F2a's recorder smoke test — the burst fallback path, kept as tooling evidence. |

Reproduce: `SENTRY_UDID=<udid> SENTRY_WIDTH=560 sh ios/scripts/record.sh <name>
<seconds> <qa-screen>`. `pull/` and `breach/` need a tap to start the sequence, so
they are driven rather than launched into — see `FEEL.md` §14.4.
