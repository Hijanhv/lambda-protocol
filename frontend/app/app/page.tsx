"use client";

import Link from "next/link";
import { useAccount, useReadContract } from "wagmi";
import { Connect } from "@/components/Connect";
import { SiteNav } from "@/components/SiteNav";
import { Pipeline } from "@/components/Pipeline";
import { HedgePanel, usePoolKeyArg } from "@/components/HedgePanel";
import { FundingPanel } from "@/components/FundingPanel";
import { PositionPanel } from "@/components/PositionPanel";
import { Card, CardContent } from "@/components/ui/card";
import { badgeVariants } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
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
      <SiteNav
        sub="LP Dashboard"
        links={[
          { href: "/", label: "Home" },
          { href: "/docs", label: "Docs" },
          { href: "/app", label: "App" },
        ]}
        rightSlot={<Connect />}
      />

      <main className="mx-auto max-w-content px-5 py-10 pb-28 md:px-8">
        <div className="mb-8">
          <h1 className="font-display text-[34px] font-semibold tracking-tight text-ink md:text-[40px]">
            Your position
          </h1>
          <p className="mt-2 font-sans text-[14.5px] text-muted">
            Deposit, watch the hedge open on Hyperliquid, and collect the funding it earns.
          </p>
        </div>

        <div className="mb-6 animate-rise">
          <Pipeline step={step} />
        </div>

        {!isConfigured && (
          <Card className="mb-6 animate-rise border-gold/40 bg-gold/[0.06]">
            <CardContent className="p-4 text-[13.5px] leading-relaxed text-ink-soft">
              <span className="font-semibold text-gold">Demo mode —</span> no contract addresses
              configured. Copy <code className="font-mono text-brand">.env.example</code> →{" "}
              <code className="font-mono text-brand">.env.local</code> and fill in the addresses from
              the deploy scripts (see <code className="font-mono text-brand">DEPLOY.md</code>), then
              restart the dev server.
            </CardContent>
          </Card>
        )}

        <div className="grid animate-rise gap-5 [animation-delay:120ms] md:grid-cols-2">
          <PositionPanel />
          <HedgePanel />
        </div>

        <div className="mt-5 animate-rise [animation-delay:200ms]">
          <FundingPanel />
        </div>

        <p className="note mt-10 max-w-2xl border-t border-edge/30 pt-6">
          The whole loop is on-chain: deposit here → the hook tracks your exact delta and emits a
          hedge signal → a Reactive Smart Contract routes it to HyperEVM → the short is opened
          through Hyperliquid&apos;s CoreWriter precompile → the funding it earns accrues back to
          you, claimable above.{" "}
          <Link href="/docs" className="font-semibold text-brand underline-offset-2 hover:underline">
            Read how it works →
          </Link>
        </p>

        {isConfigured && (
          <div className="mt-6 flex flex-wrap items-center gap-2">
            <span className="mr-2 font-sans text-[11px] font-bold uppercase tracking-[0.16em] text-muted">
              Verify on-chain
            </span>
            {[
              ["Hook", `https://sepolia.uniscan.xyz/address/${addresses.hook}`],
              ["Funding", `https://sepolia.uniscan.xyz/address/${addresses.funding}`],
              ["Reactive (Lasna)", "https://lasna.reactscan.net/"],
            ].map(([label, href]) => (
              <a
                key={label}
                href={href}
                target="_blank"
                rel="noreferrer"
                className={cn(
                  badgeVariants({ variant: "outline" }),
                  "cursor-pointer transition-colors hover:text-brand",
                )}
              >
                {label} <span className="ml-1 text-faint">↗</span>
              </a>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
