"use client";

import { useGameStore } from "@/app/lib/persistence/store";

// Contextual onboarding for the first campaign chapter ("First Light"). It reads
// the live game state and tells the player the exact next move — typed OR clicked
// (RUN). It disappears once chapter 0 is complete; by then the verbs are learned.
export default function TutorialPanel() {
  const chapter = useGameStore((s) => s.gameState.campaign.chapter);
  const missions = useGameStore((s) => s.gameState.activeMissions);
  const route = useGameStore((s) => s.gameState.route);
  const session = useGameStore((s) => s.gameState.session);
  const inventory = useGameStore((s) => s.gameState.inventory);
  const runCommand = useGameStore((s) => s.runCommand);
  const isExecuting = useGameStore((s) => s.isExecuting);

  const ch0 = missions.find((m) => m.chapterIndex === 0);
  // Only the very first chapter is hand-held; once done, the tutorial retires.
  if (chapter !== 0 || !ch0 || ch0.status === "completed") return null;

  const scanned = Array.from(session.scannedHosts ?? []).includes("hq-node");
  const steps = [
    { label: "Take the contract", cmd: `accept ${ch0.id}`, done: ch0.status === "accepted" },
    { label: "Build a proxy route — anonymity before you touch anything", cmd: "route add proxy-1", done: route.hops.length > 0 },
    { label: "Recon the target before connecting", cmd: "scan hq-node", done: scanned },
    { label: "Open a session", cmd: "connect hq-node", done: session.connectedHost === "hq-node" },
    { label: "Exfil the file to your machine", cmd: "cp /secrets.txt @local", done: inventory.some((i) => i.source === "hq-node" && i.path === "/secrets.txt") },
    { label: "Submit and ghost out", cmd: `submit ${ch0.id}`, done: false },
  ];
  const currentIndex = steps.findIndex((s) => !s.done);

  return (
    <div className="rounded-lg border border-cyan-400/40 bg-cyan-950/10 p-4 font-mono shadow-[0_0_20px_-6px] shadow-cyan-500/30">
      <div className="mb-2 flex items-center gap-2 text-[0.72rem]">
        <span className="h-2 w-2 animate-pulse rounded-full bg-cyan-400" />
        <span className="tracking-[0.2em] text-cyan-300">TUTORIAL · FIRST JOB</span>
        <span className="text-[0.58rem] text-zinc-500">type the command, or click RUN</span>
      </div>
      <ol className="space-y-1.5">
        {steps.map((step, i) => {
          const isCurrent = i === currentIndex;
          return (
            <li
              key={step.cmd}
              className={`flex items-center gap-2 text-[0.72rem] ${
                step.done ? "text-zinc-500" : isCurrent ? "text-zinc-100" : "text-zinc-600"
              }`}
            >
              <span className={`w-4 shrink-0 text-center ${step.done ? "text-cyan-400" : "text-zinc-600"}`}>
                {step.done ? "✓" : i + 1}
              </span>
              <span className="flex-1">
                {step.label}
                {(isCurrent || step.done) && (
                  <code className="ml-2 rounded bg-black/50 px-1 text-[0.66rem] text-cyan-300">{step.cmd}</code>
                )}
              </span>
              {isCurrent && (
                <button
                  disabled={isExecuting}
                  onClick={() => runCommand(step.cmd)}
                  className="shrink-0 rounded border border-cyan-600/50 bg-cyan-800/20 px-2 py-0.5 text-[0.62rem] font-semibold text-cyan-200 transition-colors hover:bg-cyan-700/30 disabled:opacity-40"
                >
                  RUN ▸
                </button>
              )}
            </li>
          );
        })}
      </ol>
    </div>
  );
}
