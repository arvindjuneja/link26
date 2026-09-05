// A thin CLI over app/lib/soc/exporter/. All logic lives there (SPEC.md §2.1).
//
//   npm run soc:export        write the 10 files and print the diff summary
//   npm run soc:check         build in memory and fail if anything on disk differs
//
// The export is deterministic: no timestamp, no git SHA, no locale, no local
// timezone. Running it twice produces zero diff.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ALL_FILE_NAMES, isContentFile, renderAll, type FileName } from "@/app/lib/soc/exporter/build";
import { diffSummary } from "@/app/lib/soc/exporter/diffSummary";

interface Args {
  out: string;
  fixtures: string;
  check: boolean;
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    out: "ios/SentryCore/Sources/SentryContent/Resources",
    fixtures: "ios/SentryCore/Sources/SentryFixtures/Resources",
    check: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--out") args.out = argv[++i];
    else if (a === "--fixtures") args.fixtures = argv[++i];
    else if (a === "--check") args.check = true;
    else if (a === "--help" || a === "-h") {
      process.stdout.write(
        "usage: tsx scripts/export-soc-content.ts [--out <dir>] [--fixtures <dir>] [--check]\n"
      );
      process.exit(0);
    } else throw new Error(`unknown argument: ${a}`);
  }
  return args;
}

function pathFor(args: Args, name: FileName): string {
  return join(isContentFile(name) ? args.out : args.fixtures, name);
}

function readIfPresent(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

function main(): void {
  const args = parseArgs(process.argv.slice(2));
  const next = renderAll();

  const previous: Record<string, string | null> = {};
  for (const name of ALL_FILE_NAMES) previous[name] = readIfPresent(pathFor(args, name));

  const summary = diffSummary({ previous, next });

  if (args.check) {
    const stale = ALL_FILE_NAMES.filter((n) => previous[n] !== next[n]);
    process.stdout.write(`${summary}\n`);
    if (stale.length > 0) {
      process.stderr.write(
        `\nsoc:check FAILED — ${stale.length} file(s) differ from a fresh export:\n` +
          stale.map((n) => `  ${pathFor(args, n)}`).join("\n") +
          "\nRun `npm run soc:export` and commit the result.\n"
      );
      process.exit(1);
    }
    process.stdout.write("soc:check OK — the committed export matches a fresh run.\n");
    return;
  }

  mkdirSync(args.out, { recursive: true });
  mkdirSync(args.fixtures, { recursive: true });
  for (const name of ALL_FILE_NAMES) writeFileSync(pathFor(args, name), next[name], "utf8");

  const bytes = ALL_FILE_NAMES.reduce((a, n) => a + Buffer.byteLength(next[n], "utf8"), 0);
  process.stdout.write(`${summary}\n`);
  process.stdout.write(`\nwrote ${ALL_FILE_NAMES.length} files, ${(bytes / 1024).toFixed(1)} KB total\n`);
  process.stdout.write(`  content  → ${args.out}\n`);
  process.stdout.write(`  fixtures → ${args.fixtures}\n`);
}

main();
