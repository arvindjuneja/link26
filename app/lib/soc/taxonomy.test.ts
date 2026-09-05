import { describe, expect, it } from "vitest";
import { SOC_CASES } from "./cases";

// ── The taxonomy invariant (decided 2026-09-05, docs/DECISION-soc-taxonomy.md) ──
//
// DEF-A is canonical: one question decides every alert — did the attack behaviour the
// rule hunts for actually happen? Didn't happen → False Positive. Happened + sanctioned
// → Benign True Positive. Happened + unsanctioned → True Positive.
//
// The 2026-07-11 playtest bug was NOT a wrong truth label — it was case copy that
// described a case using the OTHER verdict's language, so a player applying the intro
// correctly got marked wrong. These tests pin the corpus against that class of drift:
// a case's debrief must never tell the player to reach a verdict other than its truth.
// They are deliberately worded as "does not contain the sibling verdict's call-to-action"
// rather than "contains the right words", so they constrain copy without dictating it.

const CASES_BY_TRUTH = {
  "false-positive": SOC_CASES.filter((c) => c.truth === "false-positive"),
  "benign-true-positive": SOC_CASES.filter((c) => c.truth === "benign-true-positive"),
  "true-positive": SOC_CASES.filter((c) => c.truth === "true-positive"),
};

// Guard the guard: if a class ever empties, these tests would silently pass.
describe("taxonomy invariant · corpus shape", () => {
  it("ships cases in all three verdict classes", () => {
    expect(CASES_BY_TRUTH["false-positive"].length).toBeGreaterThan(0);
    expect(CASES_BY_TRUTH["benign-true-positive"].length).toBeGreaterThan(0);
    expect(CASES_BY_TRUTH["true-positive"].length).toBeGreaterThan(0);
  });
});

describe("taxonomy invariant · case copy never teaches a rival verdict", () => {
  // An FP's WHY must not tell the player this is a benign true positive: under DEF-A
  // nothing happened, so there is nothing for a sanction to cover.
  const BENIGN_CALL = /benign true positive|benign-tp|close (it )?(as )?benign/i;
  it.each(CASES_BY_TRUTH["false-positive"].map((c) => [c.id, c.why] as const))(
    "%s (false-positive) does not call itself a Benign-TP",
    (_id, why) => {
      expect(why).not.toMatch(BENIGN_CALL);
    }
  );

  // A Benign-TP's WHY must not tell the player to close FP: the behaviour DID happen,
  // so "the detection misfired" is exactly the wrong lesson (and would tempt a
  // suppression of a rule that correctly catches the malicious sibling).
  const FP_CALL = /close (it )?(as )?(a )?false positive|close fp\b|detection misfired|false alarm/i;
  it.each(CASES_BY_TRUTH["benign-true-positive"].map((c) => [c.id, c.why] as const))(
    "%s (benign-true-positive) does not tell the player to close FP",
    (_id, why) => {
      expect(why).not.toMatch(FP_CALL);
    }
  );

  // A TP's WHY must not point at either close verb.
  const CLOSE_CALL = /close (it )?(as )?(a )?false positive|close (it )?(as )?benign/i;
  it.each(CASES_BY_TRUTH["true-positive"].map((c) => [c.id, c.why] as const))(
    "%s (true-positive) does not tell the player to close it",
    (_id, why) => {
      expect(why).not.toMatch(CLOSE_CALL);
    }
  );
});

describe("taxonomy invariant · 'sanctioned' is a Benign-TP word", () => {
  // "Sanctioned" is the close-benign button's own trigger word. An FP debrief must not
  // affirm that something sanctioned the activity — that is the exact slippage that made
  // a legitimate user's own typos read as "authorized" in the 2026-07-11 playtest.
  // Negated/contrastive uses ("no ticket sanctions this", "could sanction") are fine, so
  // the pattern only matches the affirmative forms.
  const AFFIRMATIVE_SANCTION = /\b(a|the|is|was|were|are|but) sanctioned\b|\bsanctioned (it|activity|operation|run|pentest|test|drill|engagement|backup|migration|export)\b/i;
  it.each(CASES_BY_TRUTH["false-positive"].map((c) => [c.id, c.learn.concept] as const))(
    "%s (false-positive) learn.concept does not affirm a sanction",
    (_id, concept) => {
      expect(concept).not.toMatch(AFFIRMATIVE_SANCTION);
    }
  );
});
