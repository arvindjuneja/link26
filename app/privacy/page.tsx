import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy policy — SENTRY · SOC",
  description:
    "SENTRY — SOC collects no data. No account, no analytics, no network calls; your career is stored only on your device.",
};

// The privacy policy App Store guideline 5.1.1(i) requires in the app's metadata and
// inside the app itself, even at zero collection. The iOS build links here from
// Settings → About → Privacy policy, and prints the same summary inline in case the
// link cannot be opened.
//
// Static by construction: a server component with no data fetching, no client
// JavaScript and no third-party embeds — a page that claims "no analytics" should not
// be the one page on the site that loads a tracker.
export const dynamic = "force-static";

const LAST_UPDATED = "5 September 2026";
const CONTACT = "arvind@oumm.pl";

/** One numbered clause. */
function Clause({
  n,
  title,
  children,
}: {
  n: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="border-t border-white/10 pt-6">
      <h2 className="flex items-baseline gap-3 text-[15px] font-medium text-zinc-100">
        <span
          className="font-mono text-[11px] tracking-[0.18em] text-cyan-400/70"
          aria-hidden="true"
        >
          {n}
        </span>
        {title}
      </h2>
      <div className="mt-3 space-y-3 text-[14px] leading-relaxed text-zinc-400">
        {children}
      </div>
    </section>
  );
}

export default function PrivacyPage() {
  return (
    <main className="mx-auto min-h-screen w-full max-w-2xl px-6 py-16 sm:px-8">
      <header>
        <p className="font-mono text-[11px] uppercase tracking-[0.22em] text-zinc-500">
          SENTRY · SOC
        </p>
        <h1 className="mt-3 text-[28px] font-medium leading-tight text-zinc-100">
          Privacy policy
        </h1>
        <p className="mt-3 font-mono text-[12px] text-zinc-500">
          Last updated {LAST_UPDATED}
        </p>
      </header>

      {/* The whole policy in one line, before anyone has to read the clauses. */}
      <p className="mt-8 rounded-lg border border-emerald-400/25 bg-emerald-400/[0.06] p-4 text-[15px] leading-relaxed text-zinc-200">
        SENTRY — SOC collects no data. There is no account, no analytics, no
        advertising and no network request of any kind. Everything the game knows
        about you stays on your device.
      </p>

      <div className="mt-10 space-y-8">
        <Clause n="01" title="What this covers">
          <p>
            This policy covers <strong className="text-zinc-200">SENTRY — SOC</strong>,
            the iPhone game published by OUMM (Arvind Juneja, Poland). It describes the
            app, not this website.
          </p>
        </Clause>

        <Clause n="02" title="Data we collect">
          <p>
            None. The app has no sign-in, no profile, no contact form and no
            telemetry. It does not collect your name, email address, device
            identifiers, advertising identifiers, location, contacts, photos, health
            data, or usage analytics of any kind.
          </p>
          <p>
            Because nothing is collected, there is nothing for us to share, sell,
            rent, or hand to a third party — and no advertising or analytics SDK is
            bundled in the app to do it for us.
          </p>
        </Clause>

        <Clause n="03" title="Data the app stores on your device">
          <p>
            The game keeps its save on your iPhone, inside the app&rsquo;s own private
            container:
          </p>
          <ul className="ml-4 list-disc space-y-1.5 marker:text-zinc-600">
            <li>
              your career — rank, standing, cash, analyst kit, and which shifts you
              have cleared;
            </li>
            <li>an in-progress shift, so a call or a crash does not cost you the board;</li>
            <li>
              your settings — haptics, hold-to-file, coaching, and whether you have
              seen the first-run disclaimer.
            </li>
          </ul>
          <p>
            This data never leaves the device. We cannot read it. Deleting the app
            deletes it, and{" "}
            <strong className="text-zinc-200">Settings → Reset career</strong> clears
            it from inside the game.
          </p>
        </Clause>

        <Clause n="04" title="Network activity">
          <p>
            The app makes no network requests while you play. All content — cases,
            logs, copy, the daily calendar — ships inside the app bundle and works
            fully offline.
          </p>
          <p>
            The one exception is deliberate and is yours to trigger: tapping{" "}
            <em className="text-zinc-300">Privacy policy</em> in Settings → About opens
            this page in an in-app Safari view. That request goes to our host like any
            other web request; we run no analytics on this page.
          </p>
        </Clause>

        <Clause n="05" title="Purchases">
          <p>
            SENTRY — SOC is paid once, up front, through the App Store. It contains no
            in-app purchases, no subscriptions, no consumables and no advertising. We
            never see your payment details — Apple handles the transaction and tells us
            nothing about you.
          </p>
        </Clause>

        <Clause n="06" title="Children">
          <p>
            The app is rated 4+ and is safe for children in the only sense that matters
            here: it collects nothing, shows no advertising, has no chat, no
            user-generated content and no links out beyond this page.
          </p>
        </Clause>

        <Clause n="07" title="Your rights">
          <p>
            Under the GDPR and similar laws you have the right to access, correct,
            export and erase your personal data. We hold none, so there is nothing for
            us to produce or erase. The data on your device is entirely under your
            control, as described above.
          </p>
        </Clause>

        <Clause n="08" title="Changes">
          <p>
            If this policy changes, the date at the top of this page changes with it,
            and the updated policy replaces this one here. An app update that started
            collecting data would come with a new policy and a new App Store privacy
            label before it shipped.
          </p>
        </Clause>

        <Clause n="09" title="Contact">
          <p>
            Questions about this policy, or about the app:{" "}
            <a
              href={`mailto:${CONTACT}`}
              className="text-cyan-400 underline decoration-cyan-400/40 underline-offset-4 transition-colors hover:text-cyan-300"
            >
              {CONTACT}
            </a>
            .
          </p>
        </Clause>
      </div>

      <footer className="mt-14 border-t border-white/10 pt-6">
        <p className="text-[13px] leading-relaxed text-zinc-500">
          SENTRY — SOC is a fiction simulator. Every organisation, host, user and log
          line in it is fabricated; it teaches how an analyst reads evidence, never a
          working technique.
        </p>
        <Link
          href="/"
          className="mt-4 inline-block font-mono text-[12px] text-zinc-500 transition-colors hover:text-zinc-300"
        >
          &lsaquo; link26
        </Link>
      </footer>
    </main>
  );
}
