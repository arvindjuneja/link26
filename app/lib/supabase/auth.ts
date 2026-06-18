import { supabase, isSupabaseConfigured } from "./client";
import type { User, Session } from "@supabase/supabase-js";

export async function getUser(): Promise<User | null> {
  if (!isSupabaseConfigured) return null;
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

export async function getSession(): Promise<Session | null> {
  if (!isSupabaseConfigured) return null;
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

export async function signOut(): Promise<void> {
  if (!isSupabaseConfigured) return;
  await supabase.auth.signOut();
}

export function onAuthStateChange(callback: (user: User | null) => void) {
  if (!isSupabaseConfigured) {
    // Return a no-op unsubscribe function
    return { data: { subscription: { unsubscribe: () => {} } } };
  }
  return supabase.auth.onAuthStateChange((event, session) => {
    callback(session?.user ?? null);
  });
}
