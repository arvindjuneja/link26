"use client";

import { useState, useEffect } from "react";
import { Auth } from "@supabase/auth-ui-react";
import { ThemeSupa } from "@supabase/auth-ui-shared";
import { supabase, isSupabaseConfigured } from "@/app/lib/supabase/client";
import type { User } from "@supabase/supabase-js";

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAuthChange?: (user: User | null) => void;
}

export function AuthModal({ isOpen, onClose, onAuthChange }: AuthModalProps) {
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    if (!isSupabaseConfigured) return;
    
    // Check initial auth state
    supabase.auth.getUser().then(({ data: { user } }) => {
      setUser(user);
      onAuthChange?.(user);
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      const newUser = session?.user ?? null;
      setUser(newUser);
      onAuthChange?.(newUser);
      
      // Auto-close on successful sign in
      if (event === "SIGNED_IN") {
        onClose();
      }
    });

    return () => subscription.unsubscribe();
  }, [onAuthChange, onClose]);

  if (!isOpen) return null;
  
  // Show message if Supabase is not configured
  if (!isSupabaseConfigured) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center">
        <div 
          className="absolute inset-0 bg-black/80 backdrop-blur-sm"
          onClick={onClose}
        />
        <div className="relative bg-black border border-amber-500/30 rounded-lg p-6 w-full max-w-md mx-4 shadow-2xl shadow-amber-500/10">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-amber-400 font-mono text-lg">Cloud Sync Not Configured</h2>
            <button
              onClick={onClose}
              className="text-amber-500/60 hover:text-amber-400 transition-colors"
            >
              <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div className="space-y-3 text-sm font-mono">
            <p className="text-amber-400/80">
              Cloud saves require Supabase configuration.
            </p>
            <p className="text-zinc-500">
              Your game progress is saved locally in your browser.
            </p>
            <div className="border border-zinc-700 rounded p-3 bg-zinc-900/50 mt-4">
              <p className="text-zinc-400 text-xs">To enable cloud sync:</p>
              <ol className="text-zinc-500 text-xs mt-2 space-y-1 list-decimal list-inside">
                <li>Create a Supabase project</li>
                <li>Set NEXT_PUBLIC_SUPABASE_URL</li>
                <li>Set NEXT_PUBLIC_SUPABASE_ANON_KEY</li>
              </ol>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div 
        className="absolute inset-0 bg-black/80 backdrop-blur-sm"
        onClick={onClose}
      />
      
      {/* Modal */}
      <div className="relative bg-black border border-green-500/30 rounded-lg p-6 w-full max-w-md mx-4 shadow-2xl shadow-green-500/10">
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-green-400 font-mono text-lg">
            {user ? "Account" : "Sign In / Register"}
          </h2>
          <button
            onClick={onClose}
            className="text-green-500/60 hover:text-green-400 transition-colors"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {user ? (
          // Signed in state
          <div className="space-y-4">
            <div className="border border-green-500/20 rounded p-3 bg-green-500/5">
              <p className="text-green-400/60 text-xs font-mono mb-1">OPERATOR ID</p>
              <p className="text-green-400 font-mono text-sm truncate">{user.email}</p>
            </div>
            <div className="border border-green-500/20 rounded p-3 bg-green-500/5">
              <p className="text-green-400/60 text-xs font-mono mb-1">STATUS</p>
              <p className="text-green-400 font-mono text-sm">Cloud sync enabled ✓</p>
            </div>
            <button
              onClick={() => supabase.auth.signOut()}
              className="w-full py-2 px-4 border border-red-500/30 text-red-400 rounded font-mono text-sm hover:bg-red-500/10 transition-colors"
            >
              Sign Out
            </button>
          </div>
        ) : (
          // Auth UI
          <Auth
            supabaseClient={supabase}
            appearance={{
              theme: ThemeSupa,
              variables: {
                default: {
                  colors: {
                    brand: "#22c55e",
                    brandAccent: "#16a34a",
                    inputBackground: "transparent",
                    inputBorder: "#22c55e33",
                    inputBorderFocus: "#22c55e",
                    inputBorderHover: "#22c55e66",
                    inputText: "#22c55e",
                    inputLabelText: "#22c55e99",
                    inputPlaceholder: "#22c55e44",
                    messageText: "#22c55e",
                    anchorTextColor: "#22c55e",
                    anchorTextHoverColor: "#16a34a",
                  },
                  fonts: {
                    bodyFontFamily: "ui-monospace, monospace",
                    inputFontFamily: "ui-monospace, monospace",
                    buttonFontFamily: "ui-monospace, monospace",
                    labelFontFamily: "ui-monospace, monospace",
                  },
                  borderWidths: {
                    buttonBorderWidth: "1px",
                    inputBorderWidth: "1px",
                  },
                  radii: {
                    borderRadiusButton: "4px",
                    buttonBorderRadius: "4px",
                    inputBorderRadius: "4px",
                  },
                },
              },
              className: {
                container: "auth-container",
                button: "auth-button",
                input: "auth-input",
              },
            }}
            providers={["github", "google"]}
            redirectTo={typeof window !== "undefined" ? window.location.origin : undefined}
            onlyThirdPartyProviders={false}
          />
        )}

        {/* Footer hint */}
        {!user && (
          <p className="mt-4 text-green-500/40 text-xs font-mono text-center">
            Sign in to enable cloud saves across devices
          </p>
        )}
      </div>
    </div>
  );
}
