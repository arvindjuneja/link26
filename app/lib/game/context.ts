// CommandContext — the seam that keeps the game reducer PURE.
//
// The reducer must be a pure function of (state, command, context). Anything
// non-deterministic — wall-clock time, randomness, id generation — is injected
// through this context instead of being read from the ambient environment
// (Date.now(), Math.random(), crypto.randomUUID()). The live game supplies a
// real-world context; tests supply a deterministic one and get reproducible
// results.

import { hashSeed, mulberry32, type Rng } from "@/app/lib/util/rng";

export interface CommandContext {
  /** Current timestamp (ms). Replaces Date.now() inside the reducer. */
  now: number;
  /** Seeded PRNG. Replaces Math.random() inside the reducer. */
  random: Rng;
  /** Monotonic id generator for terminal lines / entities. */
  nextId: () => string;
}

/** Context for the running game: real time, real randomness, UUID ids. */
export function createLiveContext(): CommandContext {
  const base = Date.now();
  let counter = 0;
  return {
    now: base,
    random: Math.random,
    nextId: () =>
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? crypto.randomUUID()
        : `line-${base}-${counter++}`,
  };
}

/**
 * Context for tests / replays: fixed clock, seeded PRNG, counter-based ids.
 * Same seed + same now => byte-identical results.
 */
export function createDeterministicContext(
  seed: string | number = 1,
  now = 0
): CommandContext {
  const numericSeed = typeof seed === "number" ? seed : hashSeed(seed);
  const random = mulberry32(numericSeed);
  let counter = 0;
  return {
    now,
    random,
    nextId: () => `ln-${counter++}`,
  };
}
