import type { Metadata } from "next";
import SocConsole from "@/app/components/soc/SocConsole";

export const metadata: Metadata = {
  title: "SENTRY · SOC — the blue seat",
  description:
    "Tier-1 SOC analyst prototype: work a queue of alerts, pull the right logs, and make the call — True Positive / False Positive / Benign True Positive.",
};

// The blue seat lives at /soc — a self-contained career-sim prototype that reuses
// the red game's engine primitives (trace thresholds, deterministic grading,
// evidence assembly) without touching its state. See app/lib/soc/.
export default function SocPage() {
  return <SocConsole />;
}
