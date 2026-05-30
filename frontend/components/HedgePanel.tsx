"use client";

import { useReadContract } from "wagmi";
import { hook } from "@/lib/contracts";
import { addresses, currency0 } from "@/lib/config";
import { fmt, feePctFromPips } from "@/lib/format";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";

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

  const rows: [string, string, string?][] = [
    [`Live LP delta (${currency0.symbol})`, fmt(delta as bigint, dec)],
    ["Hedged delta (last signal)", fmt(state?.hedgedDelta, dec)],
    ["Short target on Hyperliquid (h · Δ)", fmt(shortTarget, dec), "text-brand"],
    ["Hedge signals sent (nonce)", state ? String(state.hedgeNonce) : "—"],
    ["Hedge ratio h", state ? `${(Number(state.hedgeRatioWad) / 1e16).toFixed(0)}%` : "—", "text-gold"],
    ["Directional fee — buy / sell", `${feePctFromPips(feeBuy as bigint)} / ${feePctFromPips(feeSell as bigint)}`],
  ];

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="eyebrow">The hedge</CardTitle>
      </CardHeader>
      <CardContent>
        <dl>
          {rows.map(([k, v, tone], i) => (
            <div key={k}>
              <div className="flex items-baseline justify-between gap-4 py-2.5">
                <dt className="font-sans text-[13px] text-muted">{k}</dt>
                <dd className={`font-mono text-[15px] tabular-nums ${tone ?? "text-ink"}`}>{v}</dd>
              </div>
              {i < rows.length - 1 && <Separator className="bg-edge/15" />}
            </div>
          ))}
        </dl>

        <p className="note mt-5">
          The short is opened on Hyperliquid through the Reactive → CoreWriter loop whenever the live
          delta drifts past the band τ; each drift bumps the nonce. The directional fee makes
          trend-continuing (informed) flow pay more — the on-chain half of the LVR defense.
        </p>
      </CardContent>
    </Card>
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
