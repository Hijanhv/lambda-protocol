"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { maxUint128, maxUint256, parseUnits } from "viem";
import { hook, erc20Abi } from "@/lib/contracts";
import { addresses, tokenMeta, currency0, hookChain } from "@/lib/config";
import { fmt } from "@/lib/format";
import { usePoolKeyArg } from "./HedgePanel";
import { useWrongNetwork } from "./NetworkBanner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

/**
 * Deposit and withdraw. The hook's deposit takes a liquidity amount `L`, but people think in
 * token amounts — so we quote `L` from a {currency0} amount using the fact that the position's
 * delta is exactly linear in liquidity: `L = amount0 · poolLiquidity / currentDelta`. Both
 * values are read live from the hook, so the quote is exact. Before the pool has any liquidity
 * (nothing to quote against) we fall back to treating the input as a raw liquidity figure.
 */
export function PositionPanel() {
  const { address } = useAccount();
  const poolKey = usePoolKeyArg();
  const { writeContract, isPending } = useWriteContract();
  const wrongNetwork = useWrongNetwork();
  const [amt, setAmt] = useState("");

  const { data: shares, refetch } = useReadContract({
    ...hook,
    functionName: "sharesOf",
    args: [poolKey[0], address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address, refetchInterval: 8000 },
  });
  const { data: ps } = useReadContract({ ...hook, functionName: "poolState", args: poolKey, query: { refetchInterval: 8000 } });
  const { data: delta } = useReadContract({ ...hook, functionName: "currentDelta", args: poolKey, query: { refetchInterval: 8000 } });

  const poolLiquidity = (ps as any)?.liquidity as bigint | undefined;
  const liveDelta = delta as bigint | undefined;

  // Quote L from the entered currency0 amount (exact: delta is linear in L). Fall back to
  // treating the input as raw L when the pool is empty and there is nothing to quote against.
  const amount0 = amt ? parseUnits(amt, currency0.decimals) : 0n;
  const canQuote = !!poolLiquidity && poolLiquidity > 0n && !!liveDelta && liveDelta > 0n;
  const aboveRange = !!poolLiquidity && poolLiquidity > 0n && (!liveDelta || liveDelta === 0n);
  const liquidity = canQuote ? (amount0 * poolLiquidity!) / liveDelta! : amount0;
  const tooBig = liquidity > maxUint128; // deposit() takes uint128 — guard the encode

  const approve = (token: `0x${string}`) =>
    writeContract({
      address: token,
      abi: erc20Abi,
      functionName: "approve",
      args: [addresses.hook, maxUint256],
      chainId: hookChain.id,
    });

  const deposit = () =>
    writeContract(
      {
        ...hook,
        functionName: "deposit",
        args: [poolKey[0], liquidity, maxUint256, maxUint256, address],
        chainId: hookChain.id,
      },
      { onSuccess: () => setTimeout(() => refetch(), 2500) }
    );

  const withdrawAll = () =>
    writeContract(
      {
        ...hook,
        functionName: "withdraw",
        args: [poolKey[0], (shares as bigint) ?? 0n, 0n, 0n, address],
        chainId: hookChain.id,
      },
      { onSuccess: () => setTimeout(() => refetch(), 2500) }
    );

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="eyebrow">Your position</CardTitle>
      </CardHeader>
      <CardContent>
        {/* Big-number "vault shares" stat */}
        <div className="mb-5 rounded-md border border-edge bg-secondary px-4 py-3.5">
          <div className="font-sans text-[12px] text-muted">Vault shares</div>
          <div className="mt-0.5 font-display text-[30px] font-semibold tabular-nums tracking-tight text-ink">
            {fmt(shares as bigint, 18)}
          </div>
        </div>

        {/* Deposit input + action */}
        <div className="flex gap-2">
          <div className="relative flex-1">
            <Input
              inputMode="decimal"
              className="pr-16"
              placeholder={`amount of ${currency0.symbol}`}
              value={amt}
              onChange={(e) => {
                const v = e.target.value.replace(/[^0-9.]/g, "");
                const i = v.indexOf(".");
                setAmt(i === -1 ? v : v.slice(0, i + 1) + v.slice(i + 1).replace(/\./g, ""));
              }}
            />
            <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 font-sans text-[12px] font-medium text-faint">
              {currency0.symbol}
            </span>
          </div>
          <Button
            className="shrink-0"
            disabled={!address || wrongNetwork || isPending || liquidity === 0n || tooBig}
            onClick={deposit}
          >
            Deposit
          </Button>
        </div>

        <div className="mt-1.5 h-4 font-mono text-[11.5px] tabular-nums text-faint">
          {amount0 > 0n &&
            (tooBig
              ? "amount too large"
              : canQuote
              ? `≈ ${fmt(liquidity, 18)} liquidity`
              : aboveRange
              ? `price is above the range, entering raw liquidity`
              : "pool not seeded yet, entering raw liquidity")}
        </div>

        {/* Approve / withdraw secondary actions */}
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <Button variant="outline" size="sm" disabled={!address || wrongNetwork} onClick={() => approve(addresses.token0)}>
            Approve {tokenMeta.token0.symbol}
          </Button>
          <Button variant="outline" size="sm" disabled={!address || wrongNetwork} onClick={() => approve(addresses.token1)}>
            Approve {tokenMeta.token1.symbol}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="ml-auto"
            disabled={!address || wrongNetwork || !shares || (shares as bigint) === 0n}
            onClick={withdrawAll}
          >
            Withdraw all
          </Button>
        </div>

        <p className="note mt-4">
          Approve both tokens once, enter how much {currency0.symbol} to add, and deposit, and the hook
          quotes the matching liquidity, pulls both token amounts, mints your shares, and (if delta
          has moved enough) fires the first hedge. Withdraw burns shares and returns your tokens plus
          accrued LP fees.
        </p>
      </CardContent>
    </Card>
  );
}
