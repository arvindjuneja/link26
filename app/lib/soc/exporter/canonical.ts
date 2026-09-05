// Canonical serialisation (SPEC.md §2.1): recursive key sort, 2-space indent, LF,
// one trailing newline, raw UTF-8 with no `\u` escaping and no BOM, JSON.stringify's
// default number formatting, and NO timestamp and NO git SHA anywhere — they would
// break byte-equality, which is the whole drift guard.
//
// Numbers are therefore JS shortest-round-trip IEEE-754 doubles; Swift's JSONDecoder
// reconstructs the identical bit pattern, so fixtures assert `==`, not a tolerance (X5).

import { createHash } from "node:crypto";

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

/** Recursively sort object keys. Arrays keep their order — order is load-bearing (D8). */
export function canonicalize(value: unknown): Json {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value === "object") {
    const src = value as Record<string, unknown>;
    const out: { [k: string]: Json } = {};
    for (const k of Object.keys(src).sort()) {
      if (src[k] === undefined) continue; // an absent field, not a null one
      out[k] = canonicalize(src[k]);
    }
    return out;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error(`non-finite number in export: ${String(value)}`);
    return value;
  }
  return value as Json;
}

/** The exact bytes written to disk. */
export function canonicalJSON(value: unknown): string {
  return `${JSON.stringify(canonicalize(value), null, 2)}\n`;
}

export function sha256Hex(input: string): string {
  return createHash("sha256").update(input, "utf8").digest("hex");
}

/** "sha256:<hex>" over the canonical JSON of the given value. */
export function contentHashOf(value: unknown): string {
  return `sha256:${sha256Hex(canonicalJSON(value))}`;
}
