import Link from "next/link";
import { Seal } from "@/components/Brand";
import { BackgroundFX } from "@/components/BackgroundFX";
import { HeroVisual } from "@/components/HeroVisual";
import { SiteNav } from "@/components/SiteNav";
import { SiteFooter } from "@/components/SiteFooter";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";

/**
 * Lambda landing, built on shadcn/ui (Button, Card, Badge, Separator, Sheet)
 * themed to Lambda's cream/ink/pink palette. Editorial feel kept via serif
 * display type, full-width section rules, a status ticker and a partners
 * marquee. Structure is carried by standalone Cards (no nested frame), so
 * borders never double up.
 */
export default function Landing() {
  return (
    <>
      <BackgroundFX />
      <div className="relative z-10">
        <Ticker />
        <SiteNav
          sub="Yield-protected liquidity"
          links={[
            { href: "#how", label: "How it works" },
            { href: "#stack", label: "Stack" },
            { href: "/docs", label: "Docs" },
          ]}
          rightSlot={
            <Button asChild size="sm">
              <Link href="/app">Launch App →</Link>
            </Button>
          }
        />
        <Hero />
        <StackStrip />
        <Idea />
        <HowItWorks />
        <HedgeBlack />
        <Partners />
        <LiveOnTestnet />
        <FinalCta />
        <SiteFooter />
      </div>
    </>
  );
}

/* ───────────────────────── top ticker ───────────────────────── */

const TICKER = [
  "Hedge loop live on Unichain Sepolia",
  "Cross-chain callback verified end-to-end, no off-chain bot",
  "136 passing Foundry tests · warning-free build",
  "A real short on Hyperliquid via the CoreWriter precompile",
  "Built on Uniswap v4 + Reactive Network",
];

function Ticker() {
  return (
    <>
      <div className="hatch h-6 border-b border-edge" />
      <div className="overflow-hidden border-b border-edge bg-background">
        <div className="flex w-max animate-marquee">
          {[0, 1].map((copy) => (
            <div key={copy} aria-hidden={copy === 1} className="flex shrink-0 items-center">
              {TICKER.map((t) => (
                <span key={t} className="flex items-center gap-2 px-5 py-1.5 font-sans text-[12px] text-ink-soft">
                  <span className="text-[13px] leading-none text-gold animate-spinSlow">λ</span>
                  {t}
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

/* ───────────────────────── hero ───────────────────────── */

function Hero() {
  return (
    <section className="relative overflow-hidden border-b border-edge">
      <div
        className="pointer-events-none absolute inset-x-0 -top-24 h-80 opacity-70"
        style={{ background: "radial-gradient(680px 280px at 68% 0%, rgba(181,39,111,0.12), transparent 70%)" }}
      />
      <div className="relative mx-auto grid max-w-content items-center gap-10 px-5 pb-14 pt-14 md:px-8 md:pt-20 lg:grid-cols-[1.05fr_1fr]">
        <div className="text-center lg:text-left">
          <Badge variant="brand" className="animate-rise">
            <span className="h-1.5 w-1.5 rounded-full bg-brand animate-pulseSoft" />
            Uniswap Hookathon · UHI9 · HK-UHI9-0872
          </Badge>

          <h1 className="mt-6 animate-rise font-display text-[40px] font-semibold leading-[1.04] tracking-tightest text-ink [animation-delay:60ms] md:text-[60px] lg:text-[64px]">
            The loss every LP pays,{" "}
            <span className="text-brand">caught and turned into yield.</span>
          </h1>

          <p className="mx-auto mt-6 max-w-xl animate-rise font-sans text-[16px] leading-relaxed text-ink-soft [animation-delay:120ms] lg:mx-0">
            A normal Uniswap position quietly bleeds about <strong className="font-semibold text-ink">11% a year</strong> to
            arbitrageurs. Lambda cancels it with a <strong className="font-semibold text-brand">real short on Hyperliquid</strong>,
            opened and resized automatically, across chains, with no off-chain bot, so the loss returns to you as funding income.
          </p>

          <div className="mt-8 flex animate-rise flex-wrap items-center justify-center gap-3 [animation-delay:180ms] lg:justify-start">
            <Button asChild size="lg">
              <Link href="/app">Launch App →</Link>
            </Button>
            <Button asChild size="lg" variant="outline">
              <Link href="/docs">Read the docs</Link>
            </Button>
          </div>

          <dl className="mx-auto mt-9 grid max-w-md animate-rise grid-cols-3 divide-x divide-edge overflow-hidden rounded-lg border border-edge [animation-delay:240ms] lg:mx-0">
            {[
              ["3", "chains, one loop"],
              ["h = 0.65", "hedge ratio"],
              ["136", "tests passing"],
            ].map(([v, k]) => (
              <div key={k} className="bg-card px-2 py-4 text-center">
                <dt className="font-display text-[20px] font-semibold tabular-nums tracking-tight text-ink">{v}</dt>
                <dd className="mt-1 font-sans text-[11px] leading-snug text-muted">{k}</dd>
              </div>
            ))}
          </dl>
        </div>

        <div className="hidden animate-rise [animation-delay:300ms] lg:block">
          <HeroVisual />
        </div>
      </div>
    </section>
  );
}

/* ───────────────────────── stack strip ───────────────────────── */

function StackStrip() {
  const blocks: [string, string][] = [
    ["Uniswap v4", "the hook"],
    ["Reactive", "the brain"],
    ["Hyperliquid", "the hedge"],
    ["Aave V3", "reserve yield"],
    ["Solady", "primitives"],
    ["Foundry", "build + fuzz"],
  ];
  return (
    <section id="stack" className="border-b border-edge">
      <div className="mx-auto max-w-content px-5 py-12 md:px-8">
        <Card className="overflow-hidden">
          <div className="tape border-b border-edge px-6 py-3">Three chains. One automatic loop.</div>
          <div className="grid grid-cols-2 divide-x divide-y divide-edge sm:grid-cols-3 md:grid-cols-6 md:divide-y-0">
            {blocks.map(([name, role]) => (
              <div key={name} className="flex flex-col items-center justify-center gap-1 px-3 py-6 text-center">
                <span className="font-display text-[16px] font-semibold text-ink">{name}</span>
                <span className="font-sans text-[11px] uppercase tracking-[0.16em] text-faint">{role}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </section>
  );
}

/* ───────────────────────── the idea ───────────────────────── */

function Idea() {
  return (
    <section className="border-b border-edge">
      <div className="mx-auto max-w-content px-5 py-14 md:px-8">
        <Eyebrow>The idea</Eyebrow>
        <h2 className="mt-3 max-w-2xl font-display text-[28px] font-semibold tracking-tight text-ink md:text-[38px]">
          The loss has a mirror image, and it pays.
        </h2>
        <p className="mt-4 max-w-2xl prose-doc">
          A short position on a perpetual exchange <em>collects</em> a funding fee that, over time, is the same size as the
          loss a Uniswap pool suffers. Same number, opposite sign. Lambda holds both at once.
        </p>

        <div className="mt-10 grid gap-4 md:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-[13px] font-semibold text-muted">
                <span className="h-2 w-2 rounded-full bg-rose" /> Normal LP
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Ledger
                rows={[
                  ["Trading fees", "+5-12% / yr", "text-ink"],
                  ["LVR drag", "−11% / yr", "text-rose"],
                  ["Funding income", "none", "text-faint"],
                ]}
                foot={["Net", "often negative", "text-rose"]}
              />
            </CardContent>
          </Card>
          <Card className="bg-secondary/40">
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-[13px] font-semibold text-brand">
                <Seal size={20} /> Lambda LP
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Ledger
                rows={[
                  ["Trading fees", "+5-12% / yr", "text-ink"],
                  ["LVR, captured back", "+7% / yr", "text-brand"],
                  ["Funding income", "+10-15% / yr", "text-brand"],
                ]}
                foot={["Net target, near-zero price risk", "≈ 18-30% / yr", "text-brand"]}
              />
            </CardContent>
          </Card>
        </div>
        <p className="mt-4 font-sans text-[12px] text-faint">
          Modeled from historical volatility and funding rates, not a guarantee. Full model in the docs.
        </p>
      </div>
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
      <Separator className="my-3 bg-line" />
      <div className="flex items-baseline justify-between">
        <span className="font-sans text-[13.5px] font-semibold text-ink">{foot[0]}</span>
        <span className={`font-mono text-[16px] font-semibold tabular-nums ${foot[2]}`}>{foot[1]}</span>
      </div>
    </div>
  );
}

/* ───────────────────────── how it works ───────────────────────── */

function HowItWorks() {
  const steps = [
    {
      n: "①",
      place: "Unichain",
      title: "The hook",
      body: "A Uniswap v4 hook owns the pool's position, tracks your exact delta, and emits a signal the moment it drifts past the band. It also charges a directional fee that makes informed flow pay the LP.",
      badge: "Live · Unichain Sepolia",
      kind: "brand" as const,
      mini: <HookMini />,
    },
    {
      n: "②",
      place: "Reactive Network",
      title: "The brain",
      body: "A Reactive Smart Contract watches that event from another chain and fires the hedge instruction in response, entirely on-chain, with no centralized bot in the loop.",
      badge: "Verified end-to-end · Lasna",
      kind: "brand" as const,
      mini: <ReactiveMini />,
    },
    {
      n: "③",
      place: "Hyperliquid",
      title: "The hedge",
      body: "A hedger calls the live CoreWriter precompile (0x3333…3333) to open or resize a real short on Hyperliquid. The funding it earns routes back to you as claimable income.",
      badge: "Built + tested · mainnet config",
      kind: "gold" as const,
      mini: <HedgeMini />,
    },
  ];
  return (
    <section id="how" className="border-b border-edge">
      <div className="mx-auto max-w-content px-5 py-14 md:px-8">
        <Eyebrow>How it works</Eyebrow>
        <h2 className="mt-3 max-w-2xl font-display text-[28px] font-semibold tracking-tight text-ink md:text-[38px]">
          One automatic loop, across three chains.
        </h2>

        <div className="mt-10 grid gap-4 md:grid-cols-3">
          {steps.map((s) => (
            <Card key={s.place} className="flex flex-col">
              <CardHeader className="pb-3">
                <div className="flex items-center gap-3">
                  <span className="font-display text-[26px] text-gold">{s.n}</span>
                  <span className="font-sans text-[11px] font-bold uppercase tracking-[0.18em] text-muted">{s.place}</span>
                </div>
                <CardTitle className="pt-1 text-[20px]">{s.title}</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-1 flex-col">
                <p className="note flex-1">{s.body}</p>
                <div className="mt-4">{s.mini}</div>
                <Badge variant={s.kind} className="mt-4 w-fit">
                  <span className={`h-1.5 w-1.5 rounded-full ${s.kind === "brand" ? "bg-brand animate-pulseSoft" : "bg-gold"}`} />
                  {s.badge}
                </Badge>
              </CardContent>
            </Card>
          ))}
        </div>

        <Card className="mt-6 bg-secondary/40">
          <CardContent className="p-5">
            <p className="font-sans text-[12.5px] leading-relaxed text-muted">
              On testnet, Reactive&apos;s Lasna can&apos;t route callbacks to HyperEVM, so legs ① and ② run live and the
              Hyperliquid leg is proven separately against real HyperEVM mainnet state on a fork (the real hedger fires a
              correct CoreWriter order, asserted byte-for-byte). On mainnet they become one loop, a one-line config change
              the Reactive Network team confirmed carries over unchanged.{" "}
              <Link href="/docs" className="font-semibold text-brand link-quiet">See the full mechanism →</Link>
            </p>
          </CardContent>
        </Card>
      </div>
    </section>
  );
}

/* ── mini-UI per leg: compact visualizations of what each leg actually does ── */

function HookMini() {
  return (
    <div className="overflow-hidden rounded-md border border-edge bg-secondary/40 font-mono text-[11px] leading-snug text-ink-soft">
      <div className="flex items-center gap-2 border-b border-edge/40 bg-background/60 px-3 py-1.5">
        <span className="h-1.5 w-1.5 rounded-full bg-brand animate-pulseSoft" />
        <span className="font-sans text-[10px] font-bold uppercase tracking-[0.14em] text-muted">Event log · v4 hook</span>
      </div>
      <pre className="overflow-hidden px-3 py-2.5 text-[11px]">
        <span className="text-brand">event</span>{" "}
        <span className="text-ink">HedgeRequested</span>
        <span className="text-faint">(</span>
        {"\n  poolId: 0x92fc…373b,\n  delta:  +1.92 ETH,\n  nonce:  17"}
        <span className="text-faint">)</span>
      </pre>
    </div>
  );
}

function ReactiveMini() {
  return (
    <div className="overflow-hidden rounded-md border border-edge bg-secondary/40">
      <div className="flex items-center gap-2 border-b border-edge/40 bg-background/60 px-3 py-1.5">
        <span className="h-1.5 w-1.5 rounded-full bg-brand animate-pulseSoft" />
        <span className="font-sans text-[10px] font-bold uppercase tracking-[0.14em] text-muted">Cross-chain callback</span>
      </div>
      <div className="px-3 py-3">
        <div className="relative h-5">
          <div className="absolute left-[10%] right-[10%] top-1/2 h-px -translate-y-1/2 bg-edge/30" />
          <span className="absolute top-1/2 h-1.5 w-1.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-brand shadow-[0_0_0_3px_rgba(181,39,111,0.18)] animate-flowX" />
          <div className="relative flex h-full items-center justify-between">
            {["Unichain", "Reactive", "Hyperliquid"].map((n) => (
              <span key={n} className="rounded-full border border-edge bg-card px-1.5 py-0.5 font-mono text-[9.5px] text-ink">
                {n}
              </span>
            ))}
          </div>
        </div>
        <div className="mt-2 font-mono text-[11px] text-ink-soft">
          callback <span className="text-brand">delivered</span>
          <span className="text-faint"> · </span>
          <span className="tabular-nums">latency 4.2s</span>
        </div>
      </div>
    </div>
  );
}

function HedgeMini() {
  return (
    <div className="overflow-hidden rounded-md border border-edge bg-secondary/40 font-mono text-[11px] leading-snug">
      <div className="flex items-center gap-2 border-b border-edge/40 bg-background/60 px-3 py-1.5">
        <span className="h-1.5 w-1.5 rounded-full bg-gold" />
        <span className="font-sans text-[10px] font-bold uppercase tracking-[0.14em] text-muted">CoreWriter · 0x3333…3333</span>
      </div>
      <pre className="overflow-hidden px-3 py-2.5 text-[11px] text-ink-soft">
        <span className="text-gold">coreWriter</span>
        <span className="text-faint">.</span>
        <span className="text-ink">sendRawAction</span>
        <span className="text-faint">(</span>
        {"\n  action:  OPEN_SHORT,\n  market:  ETH-PERP,\n  size:    1.25 ETH"}
        <span className="text-faint">)</span>
      </pre>
    </div>
  );
}

/* ─────────────── full-bleed black: the differentiator ─────────────── */

function HedgeBlack() {
  const points: [string, string][] = [
    ["Real, not simulated", "The short is a live position on Hyperliquid via the CoreWriter precompile, not a mock."],
    ["Automatic & cross-chain", "A Reactive Smart Contract routes the hedge across chains itself, with no off-chain bot in the loop."],
    ["Honest risk math", "Ships h = 0.65, about 1.4% liquidation risk over 90 days, versus ~19% for a full hedge."],
    ["Peer-reviewed", "Composes Milionis (LVR), Chitra & Diamandis, Hane, and Maire & Wunsch."],
  ];
  return (
    <section className="border-b border-edge bg-foreground text-background">
      <div className="mx-auto max-w-content px-5 py-16 md:px-8">
        <span className="font-sans text-[11px] font-bold uppercase tracking-[0.22em] text-gold-bright">The differentiator</span>
        <h2 className="mt-3 max-w-2xl font-display text-[28px] font-semibold tracking-tight text-background md:text-[40px]">
          A real hedge, opened across chains.
        </h2>
        <p className="mt-4 max-w-2xl font-sans text-[15.5px] leading-relaxed text-background/75">
          A directional fee in{" "}
          <code className="rounded bg-white/10 px-1.5 py-0.5 font-mono text-[13.5px] text-gold-bright">beforeSwap</code>{" "}
          is becoming a standard v4 pattern. Lambda has it, fuzz-tested. The part nobody else ships is the hedge itself: a
          real short on Hyperliquid, opened automatically across chains through Reactive, with no off-chain bot. That live
          cross-chain loop is the hard part, and the whole point.
        </p>

        <div className="mt-10 grid gap-4 sm:grid-cols-2">
          {points.map(([t, b]) => (
            <Card key={t} className="border-white/15 bg-white/[0.04]">
              <CardContent className="p-6">
                <div className="font-sans text-[15px] font-semibold text-background">{t}</div>
                <p className="mt-1.5 font-sans text-[13px] leading-relaxed text-background/65">{b}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ───────────────────────── partners marquee ───────────────────────── */

type PartnerSpec = { name: string; role: string; logo?: string; darkChip?: boolean };

const PARTNERS: PartnerSpec[] = [
  { name: "Uniswap v4", role: "the hook", logo: "/uniswap-logo.svg" },
  { name: "Reactive Network", role: "cross-chain automation", logo: "/reactive-wordmark.svg", darkChip: true },
  { name: "Hyperliquid", role: "the perp venue" },
  { name: "Aave V3", role: "reserve yield" },
  { name: "Solady", role: "gas-optimized primitives" },
  { name: "Foundry", role: "build + 136 tests" },
];

function Partners() {
  return (
    <section className="border-b border-edge">
      <div className="mx-auto max-w-content px-5 pt-12 text-center md:px-8">
        <Eyebrow>Built on the rails that make it possible</Eyebrow>
      </div>
      <div className="mt-8 overflow-hidden border-t border-edge py-6 [mask-image:linear-gradient(to_right,transparent,black_8%,black_92%,transparent)]">
        <div className="flex w-max animate-marquee">
          {[0, 1].map((copy) => (
            <div key={copy} aria-hidden={copy === 1} className="flex shrink-0 items-center">
              {PARTNERS.map((p) => (
                <PartnerChip key={p.name} {...p} />
              ))}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function PartnerChip({ name, role, logo, darkChip }: PartnerSpec) {
  return (
    <Card className="mx-3 flex shrink-0 flex-row items-center gap-3 px-4 py-3">
      {logo ? (
        darkChip ? (
          <span className="grid h-7 place-items-center rounded-sm bg-ink px-2">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={logo} alt="" className="h-3.5" />
          </span>
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={logo} alt="" className="h-5 w-5 object-contain" />
        )
      ) : (
        <Seal size={22} />
      )}
      <span className="leading-tight">
        <span className="block font-display text-[15px] font-semibold text-ink">{name}</span>
        <span className="block font-sans text-[11px] text-faint">{role}</span>
      </span>
    </Card>
  );
}

/* ───────────────────────── live on testnet ───────────────────────── */

const DEPLOYS: { name: string; chain: string; addr: string; href: string }[] = [
  {
    name: "LambdaHook",
    chain: "Unichain Sepolia",
    addr: "0x23C3da7CF53862Fd38640100D4FB764bE2d2cac0",
    href: "https://sepolia.uniscan.xyz/address/0x23C3da7CF53862Fd38640100D4FB764bE2d2cac0",
  },
  {
    name: "Funding",
    chain: "Unichain Sepolia",
    addr: "0x9e9bCdC6B6596fE31e9A013e760E6B3dB89293F1",
    href: "https://sepolia.uniscan.xyz/address/0x9e9bCdC6B6596fE31e9A013e760E6B3dB89293F1",
  },
  {
    name: "LambdaReactive",
    chain: "Reactive Lasna",
    addr: "0x8f9D95aa23eb0D15FB1F17af3E5913296d519f79",
    href: "https://lasna.reactscan.net/address/0x8f9D95aa23eb0D15FB1F17af3E5913296d519f79",
  },
  {
    name: "LambdaHedgeReceiver",
    chain: "Unichain Sepolia",
    addr: "0x36C7AA315e4Cd8aB7E8CADfbD5B10A3Fb03c2E0C",
    href: "https://sepolia.uniscan.xyz/address/0x36C7AA315e4Cd8aB7E8CADfbD5B10A3Fb03c2E0C",
  },
];

function short(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function LiveOnTestnet() {
  return (
    <section id="live-on-testnet" className="border-b border-edge">
      <div className="mx-auto max-w-content px-5 py-14 md:px-8">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <Eyebrow>Live on testnet</Eyebrow>
            <h2 className="mt-3 font-display text-[28px] font-semibold tracking-tight text-ink md:text-[36px]">
              Deployed, and verifiable on-chain.
            </h2>
          </div>
          <Badge variant="brand">
            <span className="h-1.5 w-1.5 rounded-full bg-brand animate-pulseSoft" />
            Unichain Sepolia · Reactive Lasna
          </Badge>
        </div>

        <Card className="mt-8 overflow-hidden">
          <div className="grid divide-y divide-edge sm:grid-cols-2 sm:divide-x">
            {DEPLOYS.map((d) => (
              <a
                key={d.name}
                href={d.href}
                target="_blank"
                rel="noopener noreferrer"
                className="group flex items-center justify-between gap-4 p-5 transition-colors hover:bg-secondary/50"
              >
                <span>
                  <span className="block font-sans text-[14px] font-semibold text-ink">{d.name}</span>
                  <span className="block font-sans text-[11.5px] text-faint">{d.chain}</span>
                </span>
                <span className="addr group-hover:text-brand">{short(d.addr)} ↗</span>
              </a>
            ))}
          </div>
        </Card>

        <p className="mt-4 font-sans text-[12.5px] leading-relaxed text-muted">
          A deposit + swap fire <code className="rounded bg-secondary px-1.5 py-0.5 font-mono text-[12px] text-brand">HedgeRequested</code>{" "}
          on Unichain; <span className="font-semibold text-ink">LambdaReactive</span> catches it on Lasna and routes a
          callback back across chains, with no off-chain bot, recording the exact hedge the protocol computed
          (<span className="font-mono text-[12px]">targetSize = 0.65 × delta</span>).
        </p>
      </div>
    </section>
  );
}

/* ───────────────────────── final cta ───────────────────────── */

function FinalCta() {
  return (
    <section className="border-b border-edge">
      <div className="mx-auto max-w-content px-5 py-16 md:px-8">
        <Card className="bg-secondary/50">
          <CardContent className="p-10 text-center md:p-14">
            <h2 className="font-display text-[30px] font-semibold tracking-tight text-ink md:text-[44px]">
              Liquidity that hedges itself.
            </h2>
            <p className="mx-auto mt-3 max-w-md font-sans text-[15px] leading-relaxed text-muted">
              Deposit, watch the hedge open on Hyperliquid, and collect the funding it earns.
            </p>
            <div className="mt-7 flex flex-wrap justify-center gap-3">
              <Button asChild size="lg">
                <Link href="/app">Launch App →</Link>
              </Button>
              <Button asChild size="lg" variant="outline">
                <Link href="/docs">Read the docs</Link>
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </section>
  );
}

/* ───────────────────────── shared ───────────────────────── */

function Eyebrow({ children }: { children: React.ReactNode }) {
  return <span className="eyebrow">{children}</span>;
}
