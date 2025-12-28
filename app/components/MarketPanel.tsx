"use client";

export default function MarketPanel() {
  return (
    <section className="space-y-2 rounded border border-zinc-800 bg-black/30 p-3 text-[0.65rem] text-zinc-200">
      <header className="text-xs uppercase tracking-[0.3em] text-zinc-500">Market</header>
      <p className="text-[0.7rem] text-zinc-400">
        New tools rotate daily. Expect proxy amplifiers, logging wipers, and pulse drones.
      </p>
      <button className="w-full rounded border border-zinc-700 px-2 py-1 text-[0.65rem] uppercase tracking-[0.2em] text-zinc-200">
        Browse (coming soon)
      </button>
    </section>
  );
}
