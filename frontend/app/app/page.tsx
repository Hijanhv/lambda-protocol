"use client";

import Link from "next/link";
import { useAccount, useReadContract } from "wagmi";
import { Connect } from "@/components/Connect";
import { Wordmark } from "@/components/Brand";
import { Pipeline } from "@/components/Pipeline";
import { HedgePanel, usePoolKeyArg } from "@/components/HedgePanel";
import { FundingPanel } from "@/components/FundingPanel";
import { PositionPanel } from "@/components/PositionPanel";
import { hook, funding } from "@/lib/contracts";
import { addresses, isConfigured } from "@/lib/config";

export default function AppPage() {
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
      <header className="sticky top-0 z-20 border-b border-line bg-canvas/80 backdrop-blur-md">
        <div className="mx-auto flex max-w-content items-center justify-between px-5 py-3.5">
          <Wordmark sub="LP Dashboard" />
          <div className="flex items-center gap-2">
            <Link href="/docs" className="btn btn-ghost hidden sm:inline-flex">
              Docs
            </Link>
            <Connect />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-content px-5 py-8 pb-28">
        <div className="mb-7 flex items-end justify-between gap-4">
          <div>
            <h1 className="font-display text-[30px] font-semibold tracking-tight text-ink">Your position</h1>
            <p className="mt-1 font-sans text-[14px] text-muted">
              Deposit, watch the hedge, and collect the funding it earns.
            </p>
          </div>
        </div>

        <div className="mb-7 animate-rise">
          <Pipeline step={step} />
        </div>

        {!isConfigured && (
          <div className="mb-7 animate-rise rounded-xl2 border border-gold/40 bg-gold/[0.08] px-5 py-4 text-[13.5px] text-ink-soft">
            <span className="font-semibold text-gold">Demo mode —</span> no contract addresses configured. Copy{" "}
            <code className="font-mono text-brand">.env.example</code> →{" "}
            <code className="font-mono text-brand">.env.local</code> and fill in the addresses from the deploy
            scripts (see <code className="font-mono text-brand">DEPLOY.md</code>), then restart the dev server.
          </div>
        )}

        <div className="grid animate-rise gap-5 [animation-delay:120ms] md:grid-cols-2">
          <PositionPanel />
          <HedgePanel />
        </div>

        <div className="mt-5 animate-rise [animation-delay:200ms]">
          <FundingPanel />
        </div>

        <p className="note mt-10 max-w-2xl border-t border-line pt-6">
          The whole loop is on-chain: deposit here → the hook tracks your exact delta and emits a
          hedge signal → a Reactive Smart Contract routes it to HyperEVM → the short is opened
          through Hyperliquid&apos;s CoreWriter precompile → the funding it earns accrues back to
          you, claimable above. <Link href="/docs" className="text-brand underline-offset-2 hover:underline">Read how it works →</Link>
        </p>

        {isConfigured && (
          <div className="mt-6 flex flex-wrap items-center gap-x-5 gap-y-2 font-mono text-[11.5px] text-faint">
            <span className="font-sans font-bold uppercase tracking-[0.16em] text-muted">Verify on-chain</span>
            <a className="transition-colors hover:text-brand" target="_blank" rel="noreferrer" href={`https://sepolia.uniscan.xyz/address/${addresses.hook}`}>Hook ↗</a>
            <a className="transition-colors hover:text-brand" target="_blank" rel="noreferrer" href={`https://sepolia.uniscan.xyz/address/${addresses.funding}`}>Funding ↗</a>
            <a className="transition-colors hover:text-brand" target="_blank" rel="noreferrer" href="https://lasna.reactscan.net/">Reactive (Lasna) ↗</a>
          </div>
        )}
      </main>
    </div>
  );
}
