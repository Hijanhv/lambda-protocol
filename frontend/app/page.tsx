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
    <main className="wrap">
      <div className="topbar">
        <div className="brand">
          <h1>
            <span className="lam">λ</span> Lambda
          </h1>
          <small>yield-protected liquidity · Uniswap v4</small>
        </div>
        <Connect />
      </div>

      <Steps step={step} />

      {!isConfigured && (
        <div className="banner">
          No contract addresses configured. Copy <code>.env.example</code> → <code>.env.local</code> and fill in
          the addresses printed by the deploy scripts (see <code>DEPLOY.md</code>), then restart the dev server.
        </div>
      )}

      <div className="grid">
        <PositionPanel />
        <HedgePanel />
      </div>
      <div style={{ height: 16 }} />
      <FundingPanel />

      <p className="note" style={{ marginTop: 24 }}>
        The whole loop is on-chain: deposit here → the hook tracks your exact delta and emits a
        hedge signal → a Reactive Smart Contract routes it to HyperEVM → the short is opened
        through Hyperliquid&apos;s CoreWriter precompile → the funding it earns accrues back to
        you, claimable above.
      </p>
    </main>
  );
}

function Steps({ step }: { step: number }) {
  const labels = ["Connect", "Deposit", "Hedge live", "Funding accrues"];
  return (
    <div className="steps">
      {labels.map((label, i) => (
        <div key={label} className={`step ${i < step ? "done" : i === step ? "active" : ""}`}>
          <span className="dot">{i < step ? "✓" : i + 1}</span>
          <span>{label}</span>
          {i < labels.length - 1 && <span className="sep">→</span>}
        </div>
      ))}
    </div>
  );
}
