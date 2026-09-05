// The composition root: everything the CLI writes and the drift guard re-runs in
// memory. Kept out of `bundle.ts` because `fixtures.ts` imports `bundle.ts`.
//
// One `contentHash` covers content + copy + daily and is stamped into all 10 files, so
// a re-encode anywhere — a `\u` escape, a BOM, a reordered key — breaks the identity
// check in `ContentTests` before any grading test runs (X6).

import { canonicalJSON, contentHashOf } from "@/app/lib/soc/exporter/canonical";
import { buildBundle } from "@/app/lib/soc/exporter/bundle";
import { COPY, verifyRichCopy } from "@/app/lib/soc/exporter/copy";
import { dailyCalendar } from "@/app/lib/soc/exporter/daily";
import { buildFixtures } from "@/app/lib/soc/exporter/fixtures";
import { verifyPins } from "@/app/lib/soc/exporter/sourcePins";
import { CONTENT_FILES, FIXTURE_FILES, type ExportedFiles } from "@/app/lib/soc/exporter/schema";

export type FileName = keyof ExportedFiles;

/** Which directory each generated file belongs in. */
export function isContentFile(name: string): boolean {
  return (CONTENT_FILES as readonly string[]).includes(name);
}

export function buildAll(): ExportedFiles {
  // Both halves of every pin, before anything is built (D4, D5, S10).
  verifyPins();
  verifyRichCopy();

  const bundle = buildBundle();
  const copy = { ...COPY, contentHash: "" };
  const daily = dailyCalendar();

  const contentHash = contentHashOf({ content: bundle, copy, daily });

  const fixtures = buildFixtures(bundle, contentHash);

  return {
    "content.json": { ...bundle, contentHash },
    "copy.json": { ...copy, contentHash },
    "daily.json": { ...daily, contentHash },
    ...fixtures,
  };
}

/** The exact bytes for every generated file, keyed by filename. */
export function renderAll(files: ExportedFiles = buildAll()): Record<FileName, string> {
  const out = {} as Record<FileName, string>;
  for (const name of [...CONTENT_FILES, ...FIXTURE_FILES]) {
    out[name] = canonicalJSON(files[name]);
  }
  return out;
}

export const ALL_FILE_NAMES: FileName[] = [...CONTENT_FILES, ...FIXTURE_FILES];
