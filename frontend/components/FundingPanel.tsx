"use client";

import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { funding } from "@/lib/contracts";
import { addresses, currency1 } from "@/lib/config";
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

  const dec1 = currency1.decimals;
  const claimable = (pending as bigint) ?? 0n;
  const hasClaim = claimable > 0n;

  return (
    <section className="panel overflow-hidden">
      {/* Pink wash to mark this as the income card. */}
      <div
        className="pointer-events-none absolute -right-24 -top-24 h-64 w-64 rounded-full opacity-70 blur-3xl"
        style={{ background: "radial-gradient(circle, rgba(181,39,111,0.14), transparent 70%)" }}
      />

      <h2 className="eyebrow mb-4">Funding income</h2>

      <div className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
        <div>
          <div className="font-sans text-[12px] text-muted">Claimable now · {currency1.symbol}</div>
          <div
            className={`mt-1 font-display text-[44px] font-semibold leading-none tabular-nums tracking-tight ${
              hasClaim ? "text-brand" : "text-ink"
            }`}
          >
            {fmt(claimable, dec1)}
          </div>
          <div className="mt-3 flex flex-wrap gap-x-6 gap-y-1 font-mono text-[12.5px] tabular-nums text-muted">
            <span>
              your share <span className="text-ink">{fmt(mirrored as bigint, 18)}</span>
            </span>
            <span>
              pool outstanding <span className="text-ink">{fmt((pool as any)?.unclaimed, dec1)}</span>
            </span>
          </div>
        </div>

        <button
          className="btn shrink-0 px-6 py-3 text-[14px]"
          disabled={!address || isPending || !hasClaim}
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

      <p className="note mt-5 max-w-2xl">
        Funding the Hyperliquid short collects flows back here and accrues to your shares pro-rata,
        time-weighted. This is the LVR loss, routed back to you as income.
      </p>
    </section>
  );
}
