"use client";

import { FormEvent, KeyboardEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { playAlert, playBeep, playClick, playScan, playConnect, playSuccess, playRouteAdd, playFileOp } from "@/app/lib/audio/sounds";

const typeClass = {
  info: "text-zinc-300",
  command: "text-lime-300",
  error: "text-rose-400",
  success: "text-emerald-400",
  warning: "text-amber-400",
  system: "text-cyan-400/70",
} as const;

// Random system flavor messages
const systemMessages = [
  "// packet fragmentation nominal",
  "// entropy pool: HEALTHY",
  "// network jitter: 12ms avg",
  "// watchdog: all green",
  "// cipher rotation complete",
  "// tunnel integrity: STABLE",
  "// proxy heartbeat detected",
  "// latency spike absorbed",
  "// hash verification OK",
  "// route cache updated",
];

// Status labels for the prompt
const statusLabel: Record<string, { text: string; color: string }> = {
  CALM: { text: "", color: "text-emerald-400" },
  ALERT: { text: "[ALERT]", color: "text-amber-400" },
  HUNT: { text: "[HUNT]", color: "text-orange-400" },
  LOCKDOWN: { text: "[LOCKDOWN]", color: "text-rose-400 animate-pulse" },
};

export default function Terminal() {
  const terminalLines = useGameStore((state) => state.terminalLines);
  const runCommand = useGameStore((state) => state.runCommand);
  const soundCue = useGameStore((state) => state.soundCue);
  const acknowledgeSoundCue = useGameStore((state) => state.acknowledgeSoundCue);
  const session = useGameStore((state) => state.gameState.session);
  const traceStatus = useGameStore((state) => state.gameState.trace.status);
  const isExecuting = useGameStore((state) => state.isExecuting);
  const [inputValue, setInputValue] = useState("");
  const [, setHistoryIndex] = useState(-1);
  const history = useGameStore((state) => state.commandHistory);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  
  // Typewriter effect state - track which lines are fully displayed
  const [displayedLineCount, setDisplayedLineCount] = useState(0);
  const [currentLineText, setCurrentLineText] = useState("");
  const [isAnimating, setIsAnimating] = useState(false);
  const animationRef = useRef<{ cancelled: boolean }>({ cancelled: false });
  
  // Cursor blink
  const [cursorVisible, setCursorVisible] = useState(true);
  
  // System message injection
  const lastSystemMsgTime = useRef(Date.now());
  const addTerminalLine = useGameStore((state) => state.addTerminalLine);

  // Blinking cursor effect
  useEffect(() => {
    const interval = setInterval(() => {
      setCursorVisible((prev) => !prev);
    }, 530);
    return () => clearInterval(interval);
  }, []);

  // Focus input on mount
  useEffect(() => {
    const timer = setTimeout(() => {
      inputRef.current?.focus();
    }, 100);
    return () => clearTimeout(timer);
  }, []);

  // Focus when not animating
  useEffect(() => {
    if (!isAnimating && !isExecuting) {
      inputRef.current?.focus();
    }
  }, [isAnimating, isExecuting]);

  // Random system message injection (atmospheric)
  useEffect(() => {
    const interval = setInterval(() => {
      const now = Date.now();
      if (session.connectedHost && !isAnimating && now - lastSystemMsgTime.current > 10000) {
        if (Math.random() > 0.65) {
          const msg = systemMessages[Math.floor(Math.random() * systemMessages.length)];
          addTerminalLine({
            id: `sys-${now}`,
            text: msg,
            type: "info",
          });
          lastSystemMsgTime.current = now;
        }
      }
    }, 6000);
    return () => clearInterval(interval);
  }, [session.connectedHost, isAnimating, addTerminalLine]);

  // Typewriter animation effect
  useEffect(() => {
    // If we're caught up, nothing to animate
    if (displayedLineCount >= terminalLines.length) {
      setIsAnimating(false);
      setCurrentLineText("");
      return;
    }

    // Cancel any previous animation
    animationRef.current.cancelled = true;
    const thisAnimation = { cancelled: false };
    animationRef.current = thisAnimation;

    setIsAnimating(true);

    const animateLines = async () => {
      let lineIdx = displayedLineCount;
      
      while (lineIdx < terminalLines.length && !thisAnimation.cancelled) {
        const line = terminalLines[lineIdx];
        const fullText = line.text;
        const isCommand = line.type === "command";
        const charDelay = isCommand ? 8 : 14;

        // Type out each character
        for (let i = 0; i <= fullText.length && !thisAnimation.cancelled; i++) {
          setCurrentLineText(fullText.slice(0, i));
          if (i < fullText.length) {
            await new Promise(resolve => setTimeout(resolve, charDelay));
          }
        }

        if (thisAnimation.cancelled) break;

        // Line complete - move to next
        lineIdx++;
        setDisplayedLineCount(lineIdx);
        setCurrentLineText("");
        
        // Small pause between lines
        if (lineIdx < terminalLines.length) {
          await new Promise(resolve => setTimeout(resolve, 40));
        }
      }

      if (!thisAnimation.cancelled) {
        setIsAnimating(false);
      }
    };

    animateLines();

    return () => {
      thisAnimation.cancelled = true;
    };
  }, [terminalLines, displayedLineCount]);

  const statusInfo = statusLabel[traceStatus] ?? statusLabel.CALM;
  
  const prompt = useMemo(() => {
    const host = session.connectedHost ?? "local";
    const dir = session.workingDir ?? "~";
    const status = statusInfo.text;
    return { host, dir, status };
  }, [session.connectedHost, session.workingDir, statusInfo.text]);

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
  }, [displayedLineCount, currentLineText]);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (!inputValue.trim() || isExecuting) return;
    // Skip animation for pending lines when user submits new command
    if (isAnimating) {
      setDisplayedLineCount(terminalLines.length);
      setCurrentLineText("");
      setIsAnimating(false);
    }
    await runCommand(inputValue);
    setInputValue("");
    setHistoryIndex(-1);
  };

  const handleHistory = useCallback((direction: "up" | "down") => {
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
  }, [history]);

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

  const renderedLines = useMemo(() => {
    const lines: React.ReactNode[] = [];
    
    // Render fully displayed lines
    for (let i = 0; i < displayedLineCount && i < terminalLines.length; i++) {
      const line = terminalLines[i];
      const isSystemLine = line.text.startsWith("//");
      lines.push(
        <pre
          key={line.id}
          className={`m-0 text-xs leading-5 ${
            isSystemLine ? "text-cyan-500/40 italic" : (typeClass[line.type as keyof typeof typeClass] ?? typeClass.info)
          }`}
        >
          {line.text}
        </pre>
      );
    }
    
    // Render currently typing line
    if (displayedLineCount < terminalLines.length && currentLineText !== undefined) {
      const currentLine = terminalLines[displayedLineCount];
      const isSystemLine = currentLineText.startsWith("//");
      lines.push(
        <pre
          key={currentLine.id + "-typing"}
          className={`m-0 text-xs leading-5 ${
            isSystemLine ? "text-cyan-500/40 italic" : (typeClass[currentLine.type as keyof typeof typeClass] ?? typeClass.info)
          }`}
        >
          {currentLineText}
          <span className="animate-pulse">▌</span>
        </pre>
      );
    }
    
    return lines;
  }, [terminalLines, displayedLineCount, currentLineText]);

  // Determine border color based on trace status
  const borderColor = traceStatus === "LOCKDOWN" 
    ? "border-rose-500/60" 
    : traceStatus === "HUNT" 
    ? "border-orange-500/50" 
    : traceStatus === "ALERT" 
    ? "border-amber-500/40" 
    : "border-zinc-800";

  // Handle click on terminal to focus input (always focus, input is never disabled)
  const handleTerminalClick = useCallback(() => {
    inputRef.current?.focus();
  }, []);

  return (
    <div 
      className={`flex h-full flex-col rounded border ${borderColor} bg-black/70 p-4 text-xs text-zinc-200 transition-colors duration-500`}
      onClick={handleTerminalClick}
    >
      <div ref={scrollRef} className="flex-1 space-y-1 overflow-y-auto pr-2 scrollbar-thin scrollbar-thumb-zinc-700 scrollbar-track-transparent">
        {renderedLines.length === 0 && (
          <div className="flex h-full items-center justify-center text-zinc-500">
            <div className="text-center">
              <div className="mb-2 text-sm font-medium tracking-wider">Link26 Terminal</div>
              <div className="text-[0.65rem]">Type <span className="text-lime-300">help</span> to see available commands</div>
            </div>
          </div>
        )}
        {renderedLines}
        
        {/* Execution indicator */}
        {isExecuting && (
          <div className="flex items-center gap-2 text-cyan-400">
            <span className="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-cyan-400" />
            <span className="text-cyan-400/70">processing...</span>
          </div>
        )}
      </div>
      
      <form onSubmit={handleSubmit} className="mt-3 flex items-center gap-2 border-t border-zinc-800 pt-3">
        <span className="font-mono text-sm">
          <span className="text-emerald-400">lnk</span>
          <span className="text-zinc-500">@</span>
          <span className="text-sky-400">{prompt.host}</span>
          <span className="text-zinc-500">:</span>
          <span className="text-zinc-300">{prompt.dir}</span>
          {prompt.status && (
            <span className={`ml-1 ${statusInfo.color}`}>{prompt.status}</span>
          )}
          <span className="text-lime-300">&gt;</span>
        </span>
        <div className="relative flex-1">
          <input
            ref={inputRef}
            value={inputValue}
            onChange={(event) => setInputValue(event.target.value)}
            onKeyDown={handleKeyDown}
            autoComplete="off"
            className="w-full border-none bg-transparent font-mono text-sm text-zinc-100 outline-none ring-0 focus:border-none focus:outline-none focus:ring-0 placeholder:text-zinc-600"
            placeholder={isExecuting ? "processing..." : isAnimating ? "" : "Type command..."}
            autoFocus
          />
          {/* Blinking cursor */}
          {!isExecuting && !isAnimating && (
            <span 
              className={`pointer-events-none absolute font-mono text-sm text-lime-400 transition-opacity duration-100 ${cursorVisible ? "opacity-100" : "opacity-0"}`}
              style={{ left: `${inputValue.length * 0.6}em`, top: 0 }}
            >
              _
            </span>
          )}
        </div>
      </form>
    </div>
  );
}
