import Dexie, { Table } from "dexie";
import { GameState } from "@/types/game";
import { SaveProvider } from "./saveProvider";

class SaveDB extends Dexie {
  saves!: Table<{ key: string; state: GameState; updatedAt: number }, string>;

  constructor() {
    super("proxytrace_save");
    this.version(1).stores({ saves: "&key,updatedAt" });
  }
}

const db = new SaveDB();

export const localSaveProvider: SaveProvider = {
  async load() {
    try {
      const saved = await db.saves.get("default");
      if (!saved?.state) return null;
      // Convert scannedHosts array back to Set
      if (saved.state.session?.scannedHosts && Array.isArray(saved.state.session.scannedHosts)) {
        saved.state.session.scannedHosts = new Set(saved.state.session.scannedHosts);
      }
      return saved.state;
    } catch (error) {
      console.error("load save failed", error);
      return null;
    }
  },
  async save(state: GameState) {
    try {
      // Convert Set to array for JSON serialization. Deep-copy `session` so we
      // never mutate the live game state (a shallow {...state} shares session).
      const serializableState = {
        ...state,
        session: {
          ...state.session,
          scannedHosts:
            state.session?.scannedHosts instanceof Set
              ? Array.from(state.session.scannedHosts)
              : state.session?.scannedHosts,
        },
      } as unknown as GameState;
      await db.saves.put({ key: "default", state: serializableState, updatedAt: Date.now() });
    } catch (error) {
      console.error("save failed", error);
    }
  },
  async clear() {
    try {
      await db.saves.delete("default");
    } catch (error) {
      console.error("clear save failed", error);
    }
  },
};
