"use client";

import { useMemo, useState } from "react";
import { CODEX } from "@/app/lib/game/contentPack";

// The "how it really works" codex — concepts + ethics, silent on procedures.
// The artifact infosec people screenshot.
export default function Codex() {
  const [open, setOpen] = useState(false);
  const byDomain = useMemo(() => {
    const map = new Map<string, typeof CODEX>();
    for (const c of CODEX) {
      if (!map.has(c.domain)) map.set(c.domain, []);
      map.get(c.domain)!.push(c);
    }
    return Array.from(map.entries());
  }, []);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="rounded border border-cyan-700/40 bg-cyan-900/10 px-3 py-1 text-cyan-300 transition-colors hover:bg-cyan-800/20"
      >
        CODEX
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-sm"
          onClick={() => setOpen(false)}
        >
          <div
            className="max-h-[85vh] w-full max-w-3xl overflow-y-auto rounded-lg border border-cyan-500/20 bg-[#05080c] p-6 font-mono shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex items-center justify-between">
              <div>
                <h2 className="text-lg font-semibold tracking-wide text-cyan-300">FIELD CODEX</h2>
                <p className="text-[0.65rem] text-zinc-500">
                  How it really works — concepts and ethics. An arcade simulator: no operational procedures.
                </p>
              </div>
              <button onClick={() => setOpen(false)} className="text-zinc-500 hover:text-zinc-300">
                ✕
              </button>
            </div>

            {byDomain.map(([domain, cards]) => (
              <section key={domain} className="mb-5">
                <h3 className="mb-2 text-[0.7rem] uppercase tracking-widest text-cyan-500/80">{domain}</h3>
                <div className="space-y-3">
                  {cards.map((c) => (
                    <div key={c.id} className="rounded border border-zinc-800 bg-black/40 p-3">
                      <div className="flex items-baseline justify-between">
                        <h4 className="text-[0.82rem] font-semibold text-zinc-200">{c.title}</h4>
                        {c.attackTechniqueId && (
                          <span className="text-[0.55rem] text-zinc-600">{c.attackTechniqueId}</span>
                        )}
                      </div>
                      <p className="mt-1 text-[0.7rem] leading-relaxed text-zinc-400">{c.concept}</p>
                      <p className="mt-1 text-[0.66rem] leading-relaxed text-cyan-300/70">
                        Why it matters: {c.whyItMatters}
                      </p>
                      <p className="mt-1 text-[0.62rem] italic leading-relaxed text-amber-300/60">{c.ethics}</p>
                    </div>
                  ))}
                </div>
              </section>
            ))}
          </div>
        </div>
      )}
    </>
  );
}
