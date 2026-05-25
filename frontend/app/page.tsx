"use client";

import { useAccount, useReadContract } from "wagmi";
import { Connect } from "@/components/Connect";
import { HedgePanel, usePoolKeyArg } from "@/components/HedgePanel";
import { FundingPanel } from "@/components/FundingPanel";
import { PositionPanel } from "@/components/PositionPanel";
import { hook, funding } from "@/lib/contracts";
import { addresses, isConfigured } from "@/lib/config";

export default function Page() {
  const { address, isConnected } = useAccount();
  const poolKey = usePoolKeyArg();

  const { data: shares } = useReadContract({
    ...hook,
    functionName: "sharesOf",
    args: [poolKey[0], address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });
  const { data: pending } = useReadContract({
    ...funding,
    functionName: "pending",
    args: [addresses.poolId, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  const hasPosition = !!shares && (shares as bigint) > 0n;
  const hasFunding = !!pending && (pending as bigint) > 0n;

  // Step index: 0 connect, 1 deposit, 2 hedge live, 3 funding accruing.
  const step = !isConnected ? 0 : !hasPosition ? 1 : !hasFunding ? 2 : 3;

  return (
    <div className="relative z-10">
      <Nav />

      <main className="mx-auto max-w-5xl px-5 pb-28">
        <Hero />

        <div className="animate-rise [animation-delay:160ms]">
          <Pipeline step={step} />
        </div>

        {!isConfigured && (
          <div className="mb-7 animate-rise rounded-xl2 border border-gold/30 bg-gold/[0.06] px-5 py-4 text-[13.5px] text-gold-bright">
            No contract addresses configured. Copy <code className="font-mono text-gold">.env.example</code> →{" "}
            <code className="font-mono text-gold">.env.local</code> and fill in the addresses printed by the deploy
            scripts (see <code className="font-mono text-gold">DEPLOY.md</code>), then restart the dev server.
          </div>
        )}

        <div className="grid animate-rise gap-5 [animation-delay:240ms] md:grid-cols-2">
          <PositionPanel />
          <HedgePanel />
        </div>

        <div className="mt-5 animate-rise [animation-delay:320ms]">
          <FundingPanel />
        </div>

        <Footnote />
      </main>
    </div>
  );
}

function Seal() {
  return (
    <span className="grid h-9 w-9 place-items-center rounded-lg bg-vermilion/[0.12] font-display text-[20px] font-700 leading-none text-vermilion shadow-seal ring-1 ring-vermilion/40">
      λ
    </span>
  );
}

function Nav() {
  return (
    <header className="sticky top-0 z-20 border-b border-white/[0.06] bg-ink-950/70 backdrop-blur-md">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-5 py-3.5">
        <div className="flex items-center gap-3">
          <Seal />
          <div className="leading-tight">
            <div className="font-display text-[19px] font-600 tracking-tightest text-paper">Lambda</div>
            <div className="font-sans text-[10.5px] uppercase tracking-[0.2em] text-faint">Yield-protected liquidity</div>
          </div>
        </div>
        <Connect />
      </div>
    </header>
  );
}

function Hero() {
  return (
    <section className="animate-rise py-12 md:py-16">
      <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3 py-1 font-sans text-[11.5px] text-muted">
        <span className="h-1.5 w-1.5 rounded-full bg-jade animate-pulseSoft" />
        Uniswap v4 · Reactive · Hyperliquid
      </div>
      <h1 className="max-w-2xl font-display text-[40px] font-500 leading-[1.04] tracking-tightest text-paper md:text-[56px]">
        Liquidity that{" "}
        <span className="italic text-gold">hedges itself.</span>
      </h1>
      <p className="mt-5 max-w-xl font-sans text-[15px] leading-relaxed text-muted">
        Deposit into the pool. A v4 hook tracks your exact delta and opens a matching short on
        Hyperliquid. The funding that short earns — the LVR you&apos;d normally bleed — accrues back
        to you.
      </p>
    </section>
  );
}

const STAGES = [
  { label: "Connect", sub: "wallet" },
  { label: "Deposit", sub: "mint shares" },
  { label: "Hedge live", sub: "short opens" },
  { label: "Funding", sub: "accrues to you" },
];

function Pipeline({ step }: { step: number }) {
  return (
    <div className="mb-7 rounded-xl2 border border-white/[0.07] bg-ink-850/50 p-5 backdrop-blur-sm">
      <div className="flex items-stretch">
        {STAGES.map((s, i) => {
          const done = i < step;
          const active = i === step;
          return (
            <div key={s.label} className="flex flex-1 items-center">
              <div className="flex flex-col items-center gap-2 text-center">
                <span
                  className={[
                    "grid h-9 w-9 place-items-center rounded-full font-mono text-[13px] transition-colors",
                    done
                      ? "bg-jade text-ink-950"
                      : active
                      ? "bg-gold text-ink-950 shadow-[0_0_22px_-4px_rgba(227,173,72,0.8)] animate-pulseSoft"
                      : "border border-white/10 bg-ink-800 text-faint",
                  ].join(" ")}
                >
                  {done ? "✓" : i + 1}
                </span>
                <div className="leading-tight">
                  <div className={`font-sans text-[12.5px] font-600 ${active || done ? "text-paper" : "text-muted"}`}>
                    {s.label}
                  </div>
                  <div className="font-sans text-[10.5px] text-faint">{s.sub}</div>
                </div>
              </div>
              {i < STAGES.length - 1 && (
                <div className="relative mx-1 mb-6 h-px flex-1 overflow-hidden bg-white/10">
                  <div
                    className={`absolute inset-0 ${done ? "bg-jade/60" : ""}`}
                  />
                  {active && (
                    <div className="absolute inset-y-0 left-0 w-1/3 animate-sheen bg-gradient-to-r from-transparent via-gold to-transparent" />
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Footnote() {
  return (
    <p className="note mt-10 max-w-2xl border-t border-white/[0.06] pt-6">
      The whole loop is on-chain: deposit here → the hook tracks your exact delta and emits a hedge
      signal → a Reactive Smart Contract routes it to HyperEVM → the short is opened through
      Hyperliquid&apos;s CoreWriter precompile → the funding it earns accrues back to you, claimable
      above.
    </p>
  );
}
