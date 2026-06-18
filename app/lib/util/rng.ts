// Deterministic, seedable RNG utilities.
//
// The game must be reproducible: the same seed + the same action sequence must
// always produce the same state. That property is what the determinism test
// guards and what server-authoritative anti-cheat will later rely on. So gameplay
// randomness must come from a *seeded* generator threaded through CommandContext,
// never from the ambient `Math.random()`.

export type Rng = () => number;

/**
 * mulberry32 — a tiny, fast, well-distributed 32-bit PRNG.
 * Returns a function yielding floats in [0, 1).
 */
export function mulberry32(seed: number): Rng {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Deterministically derive a 32-bit numeric seed from a string (FNV-1a).
 * Lets us seed worlds/missions from human-readable ids.
 */
export function hashSeed(input: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < input.length; i++) {
    h = Math.imul(h ^ input.charCodeAt(i), 16777619);
  }
  return h >>> 0;
}

/**
 * Random float in [min, max). Defaults to Math.random for incidental
 * (non-gameplay) use; pass a seeded Rng for anything that must be reproducible.
 */
export function randomBetween(min: number, max: number, rng: Rng = Math.random): number {
  return min + rng() * (max - min);
}

/** Integer in [min, max] inclusive. */
export function randomInt(min: number, max: number, rng: Rng = Math.random): number {
  return Math.floor(randomBetween(min, max + 1, rng));
}
