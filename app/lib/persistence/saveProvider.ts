import { GameState } from "@/types/game";

export interface SaveProvider {
  load(): Promise<GameState | null>;
  save(state: GameState): Promise<void>;
  clear(): Promise<void>;
}
