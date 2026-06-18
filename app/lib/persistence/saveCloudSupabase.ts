import { supabase, isSupabaseConfigured } from "@/app/lib/supabase/client";
import { GameState } from "@/types/game";
import { SaveProvider } from "./saveProvider";

/**
 * Cloud save provider using Supabase.
 * Requires authenticated user to work.
 * Falls back gracefully if not authenticated or not configured.
 */
export const cloudSaveProvider: SaveProvider = {
  async load(): Promise<GameState | null> {
    if (!isSupabaseConfigured) {
      return null;
    }
    
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        console.info("[CloudSave] No authenticated user, skipping cloud load");
        return null;
      }

      const { data, error } = await supabase
        .from("saves")
        .select("state")
        .eq("user_id", user.id)
        .single();

      if (error) {
        if (error.code === "PGRST116") {
          // No save found - not an error
          console.info("[CloudSave] No cloud save found for user");
          return null;
        }
        console.error("[CloudSave] Load error:", error);
        return null;
      }

      if (!data?.state) return null;

      // Convert scannedHosts array back to Set
      const state = data.state as GameState;
      if (state.session?.scannedHosts && Array.isArray(state.session.scannedHosts)) {
        state.session.scannedHosts = new Set(state.session.scannedHosts);
      }

      console.info("[CloudSave] Loaded cloud save");
      return state;
    } catch (error) {
      console.error("[CloudSave] Unexpected load error:", error);
      return null;
    }
  },

  async save(state: GameState): Promise<void> {
    if (!isSupabaseConfigured) {
      return;
    }
    
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        console.info("[CloudSave] No authenticated user, skipping cloud save");
        return;
      }

      // Convert Set to array for JSON serialization
      const serializableState: GameState = { ...state };
      if (serializableState.session?.scannedHosts instanceof Set) {
        (serializableState.session as { scannedHosts?: string[] }).scannedHosts = 
          Array.from(serializableState.session.scannedHosts);
      }

      const { error } = await supabase
        .from("saves")
        .upsert({
          user_id: user.id,
          state: serializableState,
          updated_at: new Date().toISOString(),
        }, {
          onConflict: "user_id",
        });

      if (error) {
        console.error("[CloudSave] Save error:", error);
        return;
      }

      console.info("[CloudSave] Saved to cloud");
    } catch (error) {
      console.error("[CloudSave] Unexpected save error:", error);
    }
  },

  async clear(): Promise<void> {
    if (!isSupabaseConfigured) {
      return;
    }
    
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { error } = await supabase
        .from("saves")
        .delete()
        .eq("user_id", user.id);

      if (error) {
        console.error("[CloudSave] Clear error:", error);
        return;
      }

      console.info("[CloudSave] Cleared cloud save");
    } catch (error) {
      console.error("[CloudSave] Unexpected clear error:", error);
    }
  },
};
