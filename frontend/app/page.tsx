import Link from "next/link";
import { Seal, Wordmark } from "@/components/Brand";

export default function Landing() {
  return (
    <div className="relative z-10">
      <Nav />
      <Hero />
      <Comparison />
      <HowItWorks />
      <Earnings />
      <Sponsors />
      <FinalCta />
      <Footer />
    </div>
  );
}

/* ───────────────────────── nav ───────────────────────── */

function Nav() {
  return (
    <header className="sticky top-0 z-30 border-b border-line/70 bg-canvas/80 backdrop-blur-md">
      <div className="mx-auto flex max-w-content items-center justify-between px-5 py-3.5">
        <Wordmark sub="Yield-protected liquidity" />
        <nav className="flex items-center gap-1 sm:gap-4">
          <a href="#how" className="link-quiet hidden px-2 sm:inline">How it works</a>
          <a href="#sponsors" className="link-quiet hidden px-2 sm:inline">Sponsors</a>
          <Link href="/docs" className="link-quiet px-2">Docs</Link>
          <Link href="/app" className="btn ml-1">Launch App</Link>
        </nav>
      </div>
    </header>
  );
}

/* ───────────────────────── hero ───────────────────────── */

function Hero() {
  return (
    <section className="mx-auto max-w-content px-5 pb-10 pt-16 md:pt-24">
      <div className="animate-rise">
        <span className="inline-flex items-center gap-2 rounded-full border border-line bg-surface px-3 py-1 font-sans text-[12px] text-muted shadow-card">
          <span className="h-1.5 w-1.5 rounded-full bg-brand animate-pulseSoft" />
          Uniswap Hookathon · UHI9
        </span>
      </div>

      <h1 className="mt-6 max-w-3xl animate-rise font-display text-[44px] font-semibold leading-[1.03] tracking-tightest text-ink [animation-delay:60ms] md:text-[68px]">
        The loss every LP pays,
        <br />
        <span className="text-brand">caught and turned into yield.</span>
      </h1>

      <p className="mt-6 max-w-xl animate-rise font-sans text-[16.5px] leading-relaxed text-ink-soft [animation-delay:120ms]">
        A normal Uniswap position quietly bleeds about <strong className="font-semibold text-ink">11% a year</strong> to
        arbitrageurs. Lambda cancels it with a{" "}
        <strong className="font-semibold text-brand">real short on Hyperliquid</strong> — opened and resized{" "}
        <strong className="font-semibold text-ink">automatically, across chains, with no off-chain bot</strong> — so the
        loss returns to you as funding income.
      </p>

      <div className="mt-8 flex animate-rise flex-wrap items-center gap-3 [animation-delay:180ms]">
        <Link href="/app" className="btn px-6 py-3 text-[15px]">Launch App →</Link>
        <Link href="/docs" className="btn btn-ghost px-6 py-3 text-[15px]">Read the docs</Link>
      </div>

      <dl className="mt-14 grid max-w-2xl animate-rise grid-cols-3 gap-6 border-t border-line pt-8 [animation-delay:240ms]">
        {[
          ["σ² / 8", "the LVR loss rate, now reclaimed"],
          ["h = 0.65", "research-backed hedge ratio"],
          ["109", "passing Foundry tests"],
        ].map(([v, k]) => (
          <div key={k}>
            <dt className="font-display text-[30px] font-semibold tabular-nums tracking-tight text-ink">{v}</dt>
            <dd className="mt-1 font-sans text-[12.5px] leading-snug text-muted">{k}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

/* ─────────────────────── comparison ─────────────────────── */

function Comparison() {
  return (
    <section className="mx-auto max-w-content px-5 py-16">
      <Eyebrow>The idea</Eyebrow>
      <h2 className="mt-3 max-w-2xl font-display text-[30px] font-semibold tracking-tight text-ink md:text-[38px]">
        The loss has a mirror image — and it pays.
      </h2>
      <p className="mt-4 max-w-2xl prose-doc">
        A short position on a perpetual exchange <em>collects</em> a funding fee that, over time, is the same size as the
        loss a Uniswap pool suffers. Same number, opposite sign. Lambda holds both at once.
      </p>

      <div className="mt-10 grid gap-5 md:grid-cols-2">
        <div className="panel">
          <div className="mb-4 inline-flex items-center gap-2 font-sans text-[13px] font-semibold text-muted">
            <span className="h-2 w-2 rounded-full bg-rose" /> Normal LP
          </div>
          <Ledger
            rows={[
              ["Trading fees", "+5–12% / yr", "text-ink"],
              ["LVR drag", "−11% / yr", "text-rose"],
              ["Funding income", "—", "text-faint"],
            ]}
            foot={["Net", "often negative", "text-rose"]}
          />
        </div>
        <div className="panel ring-1 ring-brand/15">
          <div className="mb-4 inline-flex items-center gap-2 font-sans text-[13px] font-semibold text-brand">
            <Seal size={20} /> Lambda LP
          </div>
          <Ledger
            rows={[
              ["Trading fees", "+5–12% / yr", "text-ink"],
              ["LVR, captured back", "+7% / yr", "text-brand"],
              ["Funding income", "+10–15% / yr", "text-brand"],
            ]}
            foot={["Net target, near-zero price risk", "≈ 18–30% / yr", "text-brand"]}
          />
        </div>
      </div>
      <p className="mt-4 font-sans text-[12px] text-faint">
        Modeled from historical volatility and funding rates — not a guarantee. Full model in the docs.
      </p>
    </section>
  );
}

function Ledger({
  rows,
  foot,
}: {
  rows: [string, string, string][];
  foot: [string, string, string];
}) {
  return (
    <div>
      {rows.map(([k, v, c]) => (
        <div key={k} className="flex items-baseline justify-between border-b border-dashed border-line py-2.5">
          <span className="font-sans text-[13.5px] text-muted">{k}</span>
          <span className={`font-mono text-[14px] tabular-nums ${c}`}>{v}</span>
        </div>
      ))}
      <div className="mt-3 flex items-baseline justify-between">
        <span className="font-sans text-[13.5px] font-semibold text-ink">{foot[0]}</span>
        <span className={`font-mono text-[16px] font-semibold tabular-nums ${foot[2]}`}>{foot[1]}</span>
      </div>
    </div>
  );
}

/* ─────────────────────── how it works ─────────────────────── */

function HowItWorks() {
  const steps = [
    {
      n: "①",
      place: "Unichain",
      title: "The hook",
      body: "A Uniswap v4 hook owns the pool's position, tracks your exact delta, and emits a signal the moment it drifts past the band τ. It also charges a directional fee that makes informed flow pay the LP.",
    },
    {
      n: "②",
      place: "Reactive Network",
      title: "The brain",
      body: "A Reactive Smart Contract watches that event from another chain and fires the hedge instruction in response — entirely on-chain, with no centralized bot in the loop.",
    },
    {
      n: "③",
      place: "Hyperliquid",
      title: "The hedge",
      body: "A hedger calls the live CoreWriter precompile (0x3333…3333) to open or resize a real short on Hyperliquid. The funding it earns routes back to you as claimable income.",
    },
  ];
  return (
    <section id="how" className="border-y border-line bg-surface2/50">
      <div className="mx-auto max-w-content px-5 py-16">
        <Eyebrow>How it works</Eyebrow>
        <h2 className="mt-3 max-w-2xl font-display text-[30px] font-semibold tracking-tight text-ink md:text-[38px]">
          One automatic loop, across three chains.
        </h2>
        <div className="mt-10 grid gap-5 md:grid-cols-3">
          {steps.map((s) => (
            <div key={s.place} className="panel flex flex-col">
              <div className="flex items-center gap-3">
                <span className="font-display text-[26px] text-gold">{s.n}</span>
                <span className="font-sans text-[11px] font-bold uppercase tracking-[0.18em] text-muted">{s.place}</span>
              </div>
              <h3 className="mt-3 font-display text-[20px] font-semibold text-ink">{s.title}</h3>
              <p className="mt-2 note">{s.body}</p>
            </div>
          ))}
        </div>
        <p className="mt-8">
          <Link href="/docs" className="link-quiet font-semibold text-brand">See the full mechanism, with the math →</Link>
        </p>
      </div>
    </section>
  );
}

/* ─────────────────────── earnings note ─────────────────────── */

function Earnings() {
  return (
    <section className="mx-auto max-w-content px-5 py-16">
      <div className="grid items-center gap-10 md:grid-cols-2">
        <div>
          <Eyebrow>The differentiator</Eyebrow>
          <h2 className="mt-3 font-display text-[30px] font-semibold tracking-tight text-ink md:text-[38px]">
            A real hedge, opened across chains.
          </h2>
          <p className="mt-4 prose-doc">
            A directional fee in <code>beforeSwap</code> (Nezlobin) is becoming a standard v4 pattern — Lambda has
            it, fuzz-tested. But the part nobody else ships is the hedge itself: a{" "}
            <strong>real short on Hyperliquid</strong>, opened automatically across chains through Reactive, with{" "}
            <strong>no off-chain bot</strong>. That live cross-chain loop is the hard part — and the whole point.
          </p>
        </div>
        <ul className="space-y-4">
          {[
            ["Real, not simulated", "The short is a live position on Hyperliquid via the CoreWriter precompile — not a mock."],
            ["Automatic & cross-chain", "A Reactive Smart Contract routes the hedge across chains itself — no off-chain bot in the loop."],
            ["Honest risk math", "Ships h = 0.65 — ~1.4% liquidation risk over 90 days, vs ~19% for a full hedge."],
            ["Peer-reviewed", "Composes Milionis (LVR), Chitra & Diamandis, Hane, and Maire & Wunsch."],
          ].map(([t, b]) => (
            <li key={t} className="flex gap-3">
              <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-brand" />
              <span>
                <span className="font-sans text-[15px] font-semibold text-ink">{t}. </span>
                <span className="prose-doc">{b}</span>
              </span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

/* ─────────────────────── sponsors ─────────────────────── */

function Sponsors() {
  return (
    <section id="sponsors" className="border-y border-line bg-surface2/50">
      <div className="mx-auto max-w-content px-5 py-16">
        <Eyebrow>Sponsors</Eyebrow>
        <h2 className="mt-3 max-w-2xl font-display text-[30px] font-semibold tracking-tight text-ink md:text-[38px]">
          Built on the rails that make it possible.
        </h2>

        <div className="mt-10 grid gap-5 md:grid-cols-2">
          <SponsorCard
            logo="/uniswap-logo.svg"
            name="Uniswap v4"
            role="The hook"
            body="Lambda is a first-class v4 hook: it owns the pool's single position to track exact delta, and returns a directional dynamic fee from beforeSwap — leaving the canonical swap curve untouched. A native answer to LVR, the ecosystem's most-cited open problem."
          />
          <SponsorCard
            logo="/reactive-wordmark.svg"
            name="Reactive Network"
            role="Cross-chain automation"
            body="A Reactive Smart Contract subscribes to the hook's HedgeRequested event and triggers the hedge on another chain — no off-chain bot. The cross-chain coordination isn't a convenience here; it's the thing that makes the product possible."
            darkChip
          />
        </div>

        <div className="mt-8 rounded-xl2 border border-line bg-surface p-6 shadow-card">
          <div className="mb-4 font-sans text-[11px] font-bold uppercase tracking-[0.18em] text-muted">Also built with</div>
          <div className="flex flex-wrap gap-x-8 gap-y-3 font-sans text-[14px] text-ink-soft">
            {[
              ["Hyperliquid", "live CoreWriter precompile — the real perp venue"],
              ["Aave V3", "yield for the idle insurance reserve"],
              ["Solady", "gas-optimized primitives"],
              ["Foundry", "build + fuzzing (109 tests)"],
            ].map(([n, d]) => (
              <span key={n} className="inline-flex items-baseline gap-2">
                <span className="font-semibold text-ink">{n}</span>
                <span className="text-[12.5px] text-faint">{d}</span>
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function SponsorCard({
  logo,
  name,
  role,
  body,
  wide,
  darkChip,
}: {
  logo: string;
  name: string;
  role: string;
  body: string;
  wide?: boolean;
  darkChip?: boolean;
}) {
  return (
    <div className="panel flex flex-col">
      <div className="flex h-12 items-center">
        {darkChip ? (
          <span className="inline-flex items-center rounded-lg bg-ink px-3.5 py-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={logo} alt={name} className="h-5" />
          </span>
        ) : (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img src={logo} alt={name} className={wide ? "h-6" : "h-9"} />
        )}
      </div>
      <div className="mt-4 flex items-baseline gap-2">
        <span className="font-display text-[19px] font-semibold text-ink">{name}</span>
        <span className="font-sans text-[12px] text-gold">· {role}</span>
      </div>
      <p className="mt-2 note">{body}</p>
    </div>
  );
}

/* ─────────────────────── final cta ─────────────────────── */

function FinalCta() {
  return (
    <section className="mx-auto max-w-content px-5 py-20">
      <div className="relative overflow-hidden rounded-xl2 border border-brand/20 bg-brand p-10 text-center shadow-lift md:p-16">
        <div
          className="pointer-events-none absolute -right-20 -top-20 h-64 w-64 rounded-full opacity-30 blur-3xl"
          style={{ background: "radial-gradient(circle, rgba(214,162,63,0.7), transparent 70%)" }}
        />
        <h2 className="font-display text-[32px] font-semibold tracking-tight text-canvas md:text-[44px]">
          Liquidity that hedges itself.
        </h2>
        <p className="mx-auto mt-3 max-w-md font-sans text-[15px] leading-relaxed text-canvas/80">
          Deposit, watch the hedge open on Hyperliquid, and collect the funding it earns.
        </p>
        <div className="mt-7 flex flex-wrap justify-center gap-3">
          <Link href="/app" className="btn btn-gold px-7 py-3 text-[15px]">Launch App →</Link>
          <Link href="/docs" className="btn btn-ghost border border-canvas/30 px-7 py-3 text-[15px] text-canvas ring-0 hover:bg-canvas/10">
            Read the docs
          </Link>
        </div>
      </div>
    </section>
  );
}

/* ─────────────────────── footer ─────────────────────── */

function Footer() {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto flex max-w-content flex-col items-center justify-between gap-4 px-5 py-10 sm:flex-row">
        <div className="flex items-center gap-2 font-sans text-[13px] text-muted">
          <Seal size={22} />
          <span>Lambda — the loss every LP pays, caught and turned into yield.</span>
        </div>
        <div className="flex gap-5 font-sans text-[13px]">
          <Link href="/app" className="link-quiet">App</Link>
          <Link href="/docs" className="link-quiet">Docs</Link>
          <a href="https://github.com" className="link-quiet">GitHub</a>
        </div>
      </div>
    </footer>
  );
}

/* ─────────────────────── shared ─────────────────────── */

function Eyebrow({ children }: { children: React.ReactNode }) {
  return <span className="eyebrow">{children}</span>;
}
