"use client";

import { FormEvent, KeyboardEvent, useEffect, useMemo, useRef, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { playAlert, playBeep, playClick, playScan, playConnect, playSuccess, playRouteAdd, playFileOp } from "@/app/lib/audio/sounds";

const typeClass = {
  info: "text-zinc-300",
  command: "text-lime-300",
  error: "text-rose-400",
  success: "text-emerald-400",
  warning: "text-amber-400",
} as const;

export default function Terminal() {
  const terminalLines = useGameStore((state) => state.terminalLines);
  const runCommand = useGameStore((state) => state.runCommand);
  const soundCue = useGameStore((state) => state.soundCue);
  const acknowledgeSoundCue = useGameStore((state) => state.acknowledgeSoundCue);
  const session = useGameStore((state) => state.gameState.session);
  const [inputValue, setInputValue] = useState("");
  const [, setHistoryIndex] = useState(-1);
  const history = useGameStore((state) => state.commandHistory);
  const scrollRef = useRef<HTMLDivElement>(null);

  const prompt = session.connectedHost
    ? `ptx@${session.connectedHost}:${session.workingDir ?? "/"}> `
    : "ptx> ";

  useEffect(() => {
    if (!soundCue) return;
    if (soundCue === "click") playClick();
    if (soundCue === "beep") playBeep();
    if (soundCue === "alert") playAlert();
    if (soundCue === "scan") playScan();
    if (soundCue === "connect") playConnect();
    if (soundCue === "success") playSuccess();
    if (soundCue === "routeAdd") playRouteAdd();
    if (soundCue === "fileOp") playFileOp();
    acknowledgeSoundCue();
  }, [soundCue, acknowledgeSoundCue]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [terminalLines.length]);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (!inputValue.trim()) return;
    await runCommand(inputValue);
    setInputValue("");
    setHistoryIndex(-1);
  };

  const handleHistory = (direction: "up" | "down") => {
    if (!history.length) return;
    setHistoryIndex((current) => {
      const nextIndex = direction === "up" ? Math.max(0, current + 1) : Math.min(history.length - 1, current - 1);
      const value = history[nextIndex];
      if (value !== undefined) {
        setInputValue(value);
        return nextIndex;
      }
      return current;
    });
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "ArrowUp") {
      event.preventDefault();
      handleHistory("up");
    }
    if (event.key === "ArrowDown") {
      event.preventDefault();
      handleHistory("down");
    }
  };

  const renderedLines = useMemo(
    () =>
      terminalLines.map((line) => (
        <pre
          key={line.id}
          className={`m-0 text-xs leading-5 transition-opacity ${typeClass[line.type] ?? typeClass.info}`}
        >
          {line.text}
        </pre>
      )),
    [terminalLines]
  );

  return (
    <div className="flex h-full flex-col rounded border border-zinc-800 bg-black/70 p-4 text-xs text-zinc-200">
      <div ref={scrollRef} className="flex-1 space-y-1 overflow-y-auto pr-2 scrollbar-thin scrollbar-thumb-zinc-700 scrollbar-track-transparent">
        {renderedLines.length === 0 && (
          <div className="flex h-full items-center justify-center text-zinc-500">
            <div className="text-center">
              <div className="mb-2 text-sm">ProxyTrace Terminal</div>
              <div className="text-[0.65rem]">Type <span className="text-lime-300">help</span> to see available commands</div>
            </div>
          </div>
        )}
        {renderedLines}
      </div>
      <form onSubmit={handleSubmit} className="mt-3 flex items-center gap-2 border-t border-zinc-800 pt-3">
        <span className="font-mono text-sm text-lime-300">{prompt}</span>
        <input
          value={inputValue}
          onChange={(event) => setInputValue(event.target.value)}
          onKeyDown={handleKeyDown}
          autoComplete="off"
          className="w-full bg-transparent font-mono text-sm text-zinc-100 outline-none placeholder:text-zinc-600"
          placeholder="Type command..."
          autoFocus
        />
      </form>
    </div>
  );
}
