"use client";

import { useGameStore } from "@/app/lib/persistence/store";

export default function InventoryPanel() {
  const inventory = useGameStore((state) => state.gameState.inventory);

  return (
    <section className="space-y-2 rounded border border-zinc-800 bg-black/40 p-3 text-[0.65rem] text-zinc-200">
      <header className="text-xs uppercase tracking-[0.3em] text-zinc-500">Inventory</header>
      {!inventory.length ? (
        <div className="text-[0.7rem] text-zinc-500">No items captured yet.</div>
      ) : (
        <ul className="space-y-1 text-[0.7rem]">
          {inventory.map((item) => (
            <li key={item.id} className="flex items-center justify-between rounded border border-zinc-800 px-2 py-1">
              <span className="text-white">{item.label}</span>
              <span className="text-[0.65rem] text-zinc-400">{item.source}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
