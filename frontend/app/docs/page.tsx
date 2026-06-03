import type { Metadata } from "next";
import Link from "next/link";
import { SiteNav } from "@/components/SiteNav";
import { SiteFooter } from "@/components/SiteFooter";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export const metadata: Metadata = {
  title: "How Lambda works · docs",
  description:
    "The logic behind Lambda: LVR, the LVR ⇋ funding identity, the cross-chain architecture, the delta math, the h = 0.65 hedge ratio, and the directional fee.",
};

export default function Docs() {
  return (
    <div className="relative z-10">
      <SiteNav
        sub="Docs"
        links={[
          { href: "/", label: "Home" },
          { href: "/docs", label: "Docs" },
          { href: "/app", label: "App" },
        ]}
        rightSlot={
          <Button asChild size="sm">
            <Link href="/app">Launch App →</Link>
          </Button>
        }
      />

      <main className="mx-auto max-w-3xl px-5 py-14 pb-28 md:px-8">
        <span className="eyebrow">Documentation</span>
        <h1 className="mt-3 font-display text-[40px] font-semibold leading-tight tracking-tightest text-ink md:text-[52px]">
          How Lambda works
        </h1>
        <p className="mt-4 max-w-2xl font-sans text-[17px] leading-relaxed text-ink-soft">
          Lambda turns the money liquidity providers quietly lose into money they earn. Here&apos;s the whole idea,
          first in plain English, then with the actual math and architecture.
        </p>

        <Toc />

        <article className="mt-6">
          <section id="problem">
            <h2>The problem: why LPs lose money</h2>
            <p>
              A liquidity provider deposits two assets, say ETH and USDC, into a pool so others can trade between
              them, earning a fee on each trade. The catch is in how the pool rebalances:{" "}
              <strong>when ETH&apos;s price rises, the pool sells ETH; when it falls, the pool buys.</strong> It sells
              the thing going up and buys the thing going down, the opposite of what any investor would choose.
            </p>
            <p>
              Arbitrageurs take the other side and pocket a small, certain profit every time the price moves. The 2022
              paper <em>Automated Market Making and Loss-Versus-Rebalancing</em> (Milionis, Moallemi, Roughgarden,
              Zhang) gave this loss a precise rate:
            </p>
            <Formula>loss rate = σ² / 8 &nbsp; (per unit of pool value, per unit of time)</Formula>
            <p>
              where <code>σ</code> is the asset&apos;s volatility. For an ETH/USDC pool, that works out to roughly{" "}
              <strong>11% per year</strong> handed silently from the LP to arbitrageurs. This is <strong>LVR</strong>{" "}
              (loss-versus-rebalancing), the sharper cousin of impermanent loss, and the single biggest reason
              providing liquidity is harder to profit from than it looks.
            </p>
          </section>

          <section id="solution">
            <h2>The solution: the loss is also an income stream</h2>
            <p>
              On a perpetual futures exchange, a continuous fee called the <strong>funding rate</strong> keeps the perp
              price tied to the real price. A <strong>short position collects</strong> that funding. The key fact
              Lambda is built on:
            </p>
            <Callout>
              The funding a short collects over time is, statistically, the same size as the LVR an LP loses over the
              same time. They are the same quantity with the sign flipped.
            </Callout>
            <p>
              Both are paid by the same force: people demanding exposure to a moving price. So Lambda measures exactly
              how much price exposure your position carries, opens a matching short on Hyperliquid so the risk roughly
              cancels (your position becomes near <strong>delta-neutral</strong>), and the funding that short collects
              becomes your yield. The structural loss becomes structural income.
            </p>
          </section>

          <section id="architecture">
            <h2>The architecture: one loop, three chains</h2>
            <p>Lambda is a small system spread across three places, each doing the thing it&apos;s best at, talking to each other automatically, with no off-chain bot.</p>
            <Step n="①" place="Unichain: the hook">
              A self-contained Uniswap v4 hook doubles as the protocol&apos;s vault. It owns the pool&apos;s single
              position (so its tracked liquidity is <em>exactly</em> the pool&apos;s), tracks the precise delta of every
              position, and emits a <code>HedgeRequested</code> event the instant delta drifts too far. It also charges
              a directional dynamic fee from <code>beforeSwap</code>, all without touching the swap curve.
            </Step>
            <Step n="②" place="Reactive Network: the brain">
              A Reactive Smart Contract subscribes to that event from another chain and triggers a transaction in
              response, entirely on-chain. It decides whether to act and drops replays by nonce.
            </Step>
            <Step n="③" place="Hyperliquid: the hedge">
              When the cross-chain callback reaches the hedger, it calls the live <code>CoreWriter</code> precompile at{" "}
              <code>0x3333…3333</code>, a real system contract that places real orders on Hyperliquid, and the funding
              the resulting short earns flows back to LPs. <strong>On testnet</strong>, Reactive&apos;s Lasna can&apos;t
              route callbacks to HyperEVM, so the callback lands on a <code>LambdaHedgeReceiver</code> stand-in instead,
              with the <em>same</em> authorization and monotonic-nonce rules as the real hedger; only the CoreWriter
              order itself is omitted. Promotion to mainnet is a one-line config change (see{" "}
              <a href="#mainnet" className="text-brand underline-offset-2 hover:underline">Mainnet readiness</a>).
            </Step>
          </section>

          <section id="mainnet">
            <h2>Mainnet readiness: a configuration, not a rewrite</h2>
            <p>
              Lambda is submitted on <strong>testnet</strong>, where the live pieces run against real infrastructure: a
              real v4 hook on Unichain Sepolia and real Reactive automation on Lasna. The Hyperliquid hedge leg is
              proven against <strong>real HyperEVM mainnet state on a fork</strong> — the real <code>LambdaHedger</code>{" "}
              fires a correct CoreWriter order, asserted byte-for-byte — and the CoreWriter precompile itself was probed
              live on-chain. The one limitation is external: Reactive&apos;s Lasna routes callbacks to Unichain / Base /
              Ethereum Sepolia <em>but not</em> to HyperEVM testnet; HyperEVM is a Reactive destination only on{" "}
              <strong>mainnet</strong> (chain id 999). So on testnet the cross-chain callback lands on the receiver
              stand-in described in Step ③ — an approach the <strong>Reactive Network team confirmed directly</strong>,
              noting a setup proven on a supported testnet carries over to HyperEVM mainnet unchanged.
            </p>

            <Callout>
              Promotion to mainnet is a <strong>one-line configuration change</strong>:{" "}
              <code>DESTINATION_CHAIN_ID=999</code>. The Reactive leg then targets the real <code>LambdaHedger</code> on
              HyperEVM instead of the testnet receiver, same contracts, same code.
            </Callout>

            <p>The mainnet rails Lambda will use are already live and were probed directly on-chain:</p>
            <ul className="prose-doc list-disc space-y-2 pl-5">
              <li>
                <strong>Unichain Mainnet (130)</strong>: Uniswap v4 <code>PoolManager</code> at{" "}
                <code>0x1f98…0004</code>.
              </li>
              <li>
                <strong>HyperEVM Mainnet (999)</strong>: CoreWriter precompile at <code>0x3333…3333</code>; Reactive
                callback proxy at <code>0x9299…FC4</code>.
              </li>
            </ul>

            <p>
              Full deploy runbook in{" "}
              <a
                href="https://github.com/Hijanhv/lambda-protocol#path-to-mainnet"
                target="_blank"
                rel="noopener noreferrer"
                className="text-brand underline-offset-2 hover:underline"
              >
                README → Path to mainnet ↗
              </a>
              . The live <em>testnet</em> deployment (Hook, Funding, Reactive, Receiver addresses) is on the{" "}
              <Link href="/#live-on-testnet" className="text-brand underline-offset-2 hover:underline">
                landing page&apos;s &quot;Live on testnet&quot; section
              </Link>
              .
            </p>
          </section>

          <section id="math">
            <h2>The math of the hook</h2>
            <h3>1. Delta: how much price risk a position carries</h3>
            <p>A v4 position with liquidity <code>L</code> holds, at price <code>P</code> in range <code>[Pₐ, P_b]</code>:</p>
            <Formula>x(P) = L · ( 1/√P − 1/√P_b )</Formula>
            <p>
              That <code>x(P)</code> is the position&apos;s delta. Most tools approximate it with a crude{" "}
              <code>liquidity ÷ 2</code>; Lambda computes the real curve, so the hedge actually matches the position.
            </p>

            <h3>2. The hedge, and when to adjust it</h3>
            <p>Lambda opens a short of size <code>h · x(P)</code>, where <code>h</code> is the hedge ratio. To avoid burning value on tiny adjustments, it only re-hedges when delta drifts past a band <code>τ</code>:</p>
            <Formula>re-hedge only when | current delta − hedged delta | &gt; τ</Formula>

            <h3>3. The identity that cancels the loss</h3>
            <Formula>E[ funding collected over Δt ] ≈ E[ LVR lost over Δt ] = (σ² / 8) · V · Δt</Formula>
            <p>Over a period <code>Δt</code> on a position worth <code>V</code>, the funding you collect is about the loss you&apos;d otherwise eat. Hold both, scaled by <code>h</code>, and the loss routes back to you.</p>

            <h3>4. Why the hedge ratio is 0.65, not 1.0</h3>
            <p>A full hedge cancels the most risk, but a short can be <strong>liquidated</strong> if price spikes against it. Hane (2026) finds the sweet spot:</p>
            <Formula>{`h = 1.00  →  ~19% liquidation risk over 90 days
h = 0.65  →  ~1.4% risk, still removes 93–97% of impermanent loss`}</Formula>
            <p>Lambda ships <code>h = 0.65</code>: give up a sliver of hedging to make the position dramatically safer.</p>

            <h3>5. The directional fee: defending the pool on-chain</h3>
            <p>
              Arbitrageurs profit by trading whichever direction drags the pool price toward the already-moved market
              price. So Lambda charges an asymmetric, direction-aware fee (Nezlobin&apos;s MEV-defense model):
            </p>
            <Formula>{`fee = base ± sensitivity · |drift|
  • a trade that continues the drift  (likely-informed)  →  base + surcharge
  • a trade that reverts the drift     (benign flow)       →  base − discount`}</Formula>
            <p>The toxic side of order flow ends up paying the LP, a second income stream aimed at the same leak the hedge attacks.</p>
            <p className="font-sans text-[13px] text-muted">
              The exact base, sensitivity, and cap parameters are tuned in{" "}
              <a
                href="https://github.com/Hijanhv/lambda-protocol/blob/main/CALIBRATION.md"
                target="_blank"
                rel="noopener noreferrer"
                className="text-brand underline-offset-2 hover:underline"
              >
                CALIBRATION.md ↗
              </a>{" "}
              and exercised by <code>forge test --match-contract Calibration -vv</code>.
            </p>
            <Callout>
              Directional pricing in <code>beforeSwap</code> is becoming a standard v4 pattern. Lambda implements it
              and fuzz-tests it. Lambda&apos;s distinct contribution is the other half: a <strong>real, cross-chain,
              automatic perp hedge</strong> on Hyperliquid, which no off-chain bot drives.
            </Callout>
          </section>

          <section id="security">
            <h2>Security</h2>
            <ul className="prose-doc list-disc space-y-2 pl-5">
              <li><strong>The trading curve is never modified</strong>: protection is fees + an off-pool hedge, so swap behavior stays standard.</li>
              <li><strong>Liquidation risk is bounded by design</strong> via the <code>h = 0.65</code> hedge ratio.</li>
              <li><strong>Cross-chain messages are authenticated</strong> on both legs and replay-protected by nonce.</li>
              <li><strong>An insurance reserve</strong> (earning Aave V3 yield on Base while idle) backstops rare tail cases.</li>
            </ul>
          </section>

          <section id="references">
            <h2>References</h2>
            <ol className="prose-doc list-decimal space-y-2 pl-5 text-[14px]">
              <li>Milionis, Moallemi, Roughgarden, Zhang (2022). <em>Automated Market Making and Loss-Versus-Rebalancing.</em> The σ²/8 LVR rate.</li>
              <li>Chitra, Diamandis, et al. (2025). <em>Perpetual Demand Lending Pools.</em> arXiv:2502.06028.</li>
              <li>Hane, A. (2026). <em>Optimal Hedge Ratio for Delta-Neutral Liquidity Provision under Liquidation Constraints.</em> arXiv:2603.19716. Basis for h ≈ 0.65.</li>
              <li>Maire &amp; Wunsch (2024). <em>Market Neutral Liquidity Provision.</em> LEDGER Journal.</li>
            </ol>
          </section>

          <div className="mt-14 flex flex-wrap gap-3 border-t border-edge/30 pt-8">
            <Button asChild size="lg">
              <Link href="/app">Launch App →</Link>
            </Button>
            <Button asChild size="lg" variant="outline">
              <Link href="/">Back home</Link>
            </Button>
          </div>
        </article>
      </main>

      <SiteFooter />
    </div>
  );
}

/* ─────────────────────── helpers ─────────────────────── */

function Toc() {
  const items = [
    ["problem", "The problem"],
    ["solution", "The solution"],
    ["architecture", "Architecture"],
    ["mainnet", "Mainnet readiness"],
    ["math", "The math"],
    ["security", "Security"],
    ["references", "References"],
  ];
  return (
    <Card className="mt-10">
      <CardContent className="p-5">
        <div className="mb-3 font-sans text-[11px] font-bold uppercase tracking-[0.18em] text-muted">On this page</div>
        <ol className="grid gap-x-6 gap-y-2 font-sans text-[14px] sm:grid-cols-2">
          {items.map(([id, label], i) => (
            <li key={id}>
              <a href={`#${id}`} className="link-quiet">
                <span className="mr-2 font-mono text-[12px] text-gold">{String(i + 1).padStart(2, "0")}</span>
                {label}
              </a>
            </li>
          ))}
        </ol>
      </CardContent>
    </Card>
  );
}

function Formula({ children }: { children: React.ReactNode }) {
  return (
    <pre className="my-5 overflow-x-auto rounded-md border border-edge bg-secondary px-5 py-4 font-mono text-[13.5px] leading-relaxed text-ink">
      {children}
    </pre>
  );
}

function Callout({ children }: { children: React.ReactNode }) {
  return (
    <Card className="my-5 border-l-4 border-l-brand bg-brand/[0.05]">
      <CardContent className="py-4 pl-5 pr-4">
        <p className="prose-doc !mb-0 font-medium text-ink">{children}</p>
      </CardContent>
    </Card>
  );
}

function Step({ n, place, children }: { n: string; place: string; children: React.ReactNode }) {
  return (
    <Card className="my-4">
      <CardContent className="flex gap-4 p-5">
        <span className="font-display text-[28px] leading-none text-gold">{n}</span>
        <div>
          <div className="font-sans text-[11px] font-bold uppercase tracking-[0.16em] text-brand">{place}</div>
          <p className="prose-doc !mb-0 mt-1.5">{children}</p>
        </div>
      </CardContent>
    </Card>
  );
}
