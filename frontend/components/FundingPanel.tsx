"use client";

import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { funding } from "@/lib/contracts";
import { addresses, tokenMeta } from "@/lib/config";
import { fmt } from "@/lib/format";

/** The income side: funding accrued to the connected LP, with a claim button. */
export function FundingPanel() {
  const { address } = useAccount();
  const { writeContract, isPending } = useWriteContract();

  const { data: pending, refetch } = useReadContract({
    ...funding,
    functionName: "pending",
    args: [addresses.poolId, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address, refetchInterval: 8000 },
  });
  const { data: pool } = useReadContract({ ...funding, functionName: "poolInfo", args: [addresses.poolId] });
  const { data: mirrored } = useReadContract({
    ...funding,
    functionName: "sharesOf",
    args: [addresses.poolId, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  const dec1 = tokenMeta.token1.decimals;
  const claimable = (pending as bigint) ?? 0n;

  return (
    <div className="card">
      <h2>Funding income</h2>
      <div className="stat">
        <span className="k">Claimable now ({tokenMeta.token1.symbol})</span>
        <span className={`v ${claimable > 0n ? "pos" : ""}`}>{fmt(claimable, dec1)}</span>
      </div>
      <div className="stat">
        <span className="k">Your share of the vault</span>
        <span className="v">{fmt(mirrored as bigint, 18)}</span>
      </div>
      <div className="stat">
        <span className="k">Pool funding outstanding</span>
        <span className="v">{fmt((pool as any)?.unclaimed, dec1)}</span>
      </div>
      <div style={{ marginTop: 14 }}>
        <button
          className="btn accent2"
          disabled={!address || isPending || claimable === 0n}
          onClick={() =>
            writeContract(
              { ...funding, functionName: "claim", args: [addresses.poolId] },
              { onSuccess: () => setTimeout(() => refetch(), 2500) }
            )
          }
        >
          {isPending ? "Claiming…" : "Claim funding"}
        </button>
      </div>
      <p className="note">
        Funding the Hyperliquid short collects flows back here and accrues to your shares
        pro-rata, time-weighted. This is the LVR loss, routed back to you as income.
      </p>
    </div>
  );
}
