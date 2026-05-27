"use client";

import { useReadContract } from "wagmi";
import { hook } from "@/lib/contracts";
import { addresses, currency0 } from "@/lib/config";
import { fmt, feePctFromPips } from "@/lib/format";

/**
 * The hedge side of the position: the live LP delta the protocol tracks, the last hedge
 * signal it emitted (nonce + the short target the HyperEVM hedger holds), and the current
 * directional fee in each swap direction.
 */
export function HedgePanel() {
  const poolKey = usePoolKeyArg();

  const poll = { refetchInterval: 8000 } as const;
  const { data: ps } = useReadContract({ ...hook, functionName: "poolState", args: poolKey, query: poll });
  const { data: delta } = useReadContract({ ...hook, functionName: "currentDelta", args: poolKey, query: poll });
  const { data: feeBuy } = useReadContract({ ...hook, functionName: "previewFee", args: [poolKey?.[0], false], query: poll });
  const { data: feeSell } = useReadContract({ ...hook, functionName: "previewFee", args: [poolKey?.[0], true], query: poll });

  const state = ps as any;
  const dec = currency0.decimals;
  // Short the protocol targets on Hyperliquid = h · (delta at last signal).
  const shortTarget =
    state?.hedgedDelta != null ? (BigInt(state.hedgedDelta) * BigInt(state.hedgeRatioWad)) / 10n ** 18n : 0n;

  return (
    <section className="panel">
      <h2 className="eyebrow mb-4">The hedge</h2>

      <div className="stat-row">
        <span className="stat-key">Live LP delta ({currency0.symbol})</span>
        <span className="stat-val">{fmt(delta as bigint, dec)}</span>
      </div>
      <div className="stat-row">
        <span className="stat-key">Hedged delta (last signal)</span>
        <span className="stat-val">{fmt(state?.hedgedDelta, dec)}</span>
      </div>
      <div className="stat-row">
        <span className="stat-key">Short target on Hyperliquid (h · Δ)</span>
        <span className="stat-val text-brand">{fmt(shortTarget, dec)}</span>
      </div>
      <div className="stat-row">
        <span className="stat-key">Hedge signals sent (nonce)</span>
        <span className="stat-val">{state ? String(state.hedgeNonce) : "—"}</span>
      </div>
      <div className="stat-row">
        <span className="stat-key">Hedge ratio h</span>
        <span className="stat-val text-gold">
          {state ? `${(Number(state.hedgeRatioWad) / 1e16).toFixed(0)}%` : "—"}
        </span>
      </div>
      <div className="stat-row">
        <span className="stat-key">Directional fee — buy / sell</span>
        <span className="stat-val">
          {feePctFromPips(feeBuy as bigint)} / {feePctFromPips(feeSell as bigint)}
        </span>
      </div>

      <p className="note mt-4">
        The short is opened on Hyperliquid through the Reactive → CoreWriter loop whenever the live
        delta drifts past the band τ; each drift bumps the nonce. The directional fee makes
        trend-continuing (informed) flow pay more — the on-chain half of the LVR defense.
      </p>
    </section>
  );
}

/** The PoolKey tuple the hook's view functions expect, assembled from env. */
export function usePoolKeyArg() {
  // The hook's poolState/currentDelta take a PoolKey; we reconstruct it from configured tokens.
  // currency0/1 must be sorted ascending (Uniswap convention).
  const [c0, c1] =
    addresses.token0.toLowerCase() < addresses.token1.toLowerCase()
      ? [addresses.token0, addresses.token1]
      : [addresses.token1, addresses.token0];
  const key = {
    currency0: c0,
    currency1: c1,
    fee: 0x800000, // dynamic-fee flag
    tickSpacing: Number(process.env.NEXT_PUBLIC_TICK_SPACING ?? 60),
    hooks: addresses.hook,
  };
  return [key] as const;
}
