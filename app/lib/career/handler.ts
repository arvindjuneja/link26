// The point of contact — the "someone's in your corner" layer that makes the career
// feel alive. Vale is the blue seat's shift-lead / mentor (warm, straight, roots for
// you); Mercer is the red handler (terse ex-trade) who occasionally reaches across the
// seats. Messages are DERIVED from career state + the thing that just happened, so the
// inbox reacts to how you actually did — praise after a clean shift, a straight word
// after a breach, a nudge toward the next rung, a tip when you can afford kit.
//
// Pure: given state + event → the messages to show. No I/O.

import {
  KIT,
  nextRank,
  owns,
  rankFor,
  type CareerState,
  type Rank,
} from "@/app/lib/career/state";

export interface HandlerMessage {
  id: string;
  from: string;
  role: string;
  subject: string;
  body: string;
  tone: "warm" | "warn" | "tip" | "milestone";
}

export interface HandlerEvent {
  type?: "shift-clean" | "shift-rough" | "shift-breached";
  rankUp?: Rank | null;
  /** shifts that just unlocked (id + label) */
  unlocked?: { id: string; label: string }[];
}

const VALE = { from: "Vale", role: "your shift lead" };
const MERCER = { from: "Mercer", role: "handler · red seat" };

/** The inbox to show on the career hub, given state + the latest event. Ordered:
 *  what-just-happened first, then standing tips, capped so it never becomes a wall. */
export function inboxFor(c: CareerState, ev: HandlerEvent = {}): HandlerMessage[] {
  const out: HandlerMessage[] = [];

  if (ev.type === "shift-clean") {
    const nr = nextRank(c.standing);
    out.push({
      id: "ev-clean",
      ...VALE,
      tone: "warm",
      subject: "Clean shift — nice work",
      body: nr
        ? `Sharp reads all the way through. +40 standing. Keep them clean and you're ${nr.min - c.standing} short of ${nr.label} — then I open a harder queue for you.`
        : `Sharp reads all the way through. +40 standing. You're at the top of what I can put you up for — Tier-2's next, and that's earned, not given.`,
    });
  } else if (ev.type === "shift-rough") {
    out.push({
      id: "ev-rough",
      ...VALE,
      tone: "warn",
      subject: "Rough one — that's the job",
      body: "A few calls were off. It happens to everyone on this desk. Re-read the debriefs — the misses are where the read gets sharper. Standing barely moved; clean shifts are how you climb, not volume.",
    });
  } else if (ev.type === "shift-breached") {
    out.push({
      id: "ev-breach",
      ...VALE,
      tone: "warn",
      subject: "Something got past you",
      body: "A real one got closed and dwelt. Every analyst has that night once. The lesson is which log you skipped before you called it — pull the answering source next time. We're still in your corner.",
    });
  }

  if (ev.rankUp) {
    const cross = ev.rankUp.id === "t2";
    out.push({
      id: "ev-rankup",
      ...(cross ? MERCER : VALE),
      tone: "milestone",
      subject: `You made ${ev.rankUp.label}`,
      body: cross
        ? "Mercer here. Your shift lead's been talking you up. You've got the read now — and the other chair's a lot easier once you've sat in this one. When you're ready."
        : `That's ${ev.rankUp.label}. I flagged you to the lead. This is the ladder, and you're climbing it the right way — by being right.`,
    });
  }

  for (const u of ev.unlocked ?? []) {
    const handoff = u.id === "handoff-shift";
    out.push({
      id: `ev-unlock-${u.id}`,
      ...(handoff ? MERCER : VALE),
      tone: "milestone",
      subject: handoff ? "The other chair is open to you" : `New queue: ${u.label}`,
      body: handoff
        ? "Mercer. Your lead says you're ready to see the runs I sent you from the blue side. That's Shift 4 — the same board, the other chair. Go find out what your own tradecraft looks like to a defender."
        : `${u.label} is open to you now — you earned it. Harder alerts, same read.`,
    });
  }

  // Cross-seat nudge: competent enough for the handoff desk, but hasn't sat in the
  // red chair yet — pull the player to the other seat (running a red mission opens it).
  if (c.standing >= 90 && c.redRunsDone < 1) {
    out.push({
      id: "tip-redrun",
      ...MERCER,
      tone: "tip",
      subject: "Come sit in the other chair",
      body: "Mercer. Your lead says you've got the reads down. Want to see what you're actually defending against? Run one contract in the red seat — do that and the handoff desk opens: your own tradecraft, seen from the blue side.",
    });
  }

  // Standing tip: you can afford kit that pays for itself.
  const feed = KIT.find((k) => k.id === "intel-feed");
  if (feed && c.cash >= feed.cost && !owns(c, "intel-feed")) {
    out.push({
      id: "tip-kit",
      ...VALE,
      tone: "tip",
      subject: "You've banked enough for the intel feed",
      body: `You're at ${c.cash}¢ — enough for the ${feed.label}. Grab it before your next shift; it pre-pulls enrichment on every case and saves you shift-time. This is what the cash is for.`,
    });
  }

  // First-run welcome (only when genuinely fresh and nothing else to say).
  if (out.length === 0 && c.shiftsCleaned === 0 && c.standing === 0) {
    out.push({
      id: "welcome",
      ...VALE,
      tone: "warm",
      subject: "Welcome to the desk",
      body: "I'm Vale — I run this shift. New here? Start with the fundamentals queue. Clean shifts move you up the ladder and I'll open harder work as you earn it; the cash from the job buys kit that makes you faster. You're not alone on this — ping me any time. Go get one.",
    });
  }

  return out.slice(0, 4);
}
