"use client";

import { useEffect, useState } from "react";

const KEY = "link26_desktop_hint_v1";

// The operator cockpit (live WebGL map + terminal + boards) is built for a wide
// screen. On phones it renders but is cramped — this sets expectations without
// blocking play. Mobile-only (lg:hidden) and dismissible.
export default function DesktopHint() {
  const [show, setShow] = useState(false);
  useEffect(() => {
    try {
      if (!localStorage.getItem(KEY)) setShow(true);
    } catch {
      setShow(true);
    }
  }, []);
  if (!show) return null;
  return (
    <div className="flex items-start gap-3 rounded border border-amber-500/30 bg-amber-500/5 px-3 py-2 text-[0.72rem] text-amber-200/90 lg:hidden">
      <span aria-hidden>🖥️</span>
      <p className="flex-1 leading-snug">
        The operator cockpit (live map + terminal) is built for a bigger screen — it works on a
        phone but it&apos;s cramped. For the full experience, open Link26 on a laptop or desktop.
        The <span className="text-emerald-300">SOC desk</span> reads fine on mobile.
      </p>
      <button
        onClick={() => {
          try {
            localStorage.setItem(KEY, "1");
          } catch {
            /* ignore */
          }
          setShow(false);
        }}
        className="shrink-0 rounded border border-amber-500/30 px-2 py-0.5 text-[0.65rem] text-amber-200/80 transition-colors hover:bg-amber-500/10"
      >
        got it
      </button>
    </div>
  );
}
