"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { maxUint256, parseUnits } from "viem";
import { hook, erc20Abi } from "@/lib/contracts";
import { addresses, tokenMeta } from "@/lib/config";
import { fmt } from "@/lib/format";
import { usePoolKeyArg } from "./HedgePanel";

/**
 * Deposit and withdraw. The hook takes a liquidity amount (front-ends convert token amounts to
 * L); for the demo we accept a raw liquidity figure and pass generous slippage bounds, which is
 * the simplest honest mapping until a quoter is wired in.
 */
export function PositionPanel() {
  const { address } = useAccount();
  const poolKey = usePoolKeyArg();
  const { writeContract, isPending } = useWriteContract();
  const [liq, setLiq] = useState("");

  const { data: shares, refetch } = useReadContract({
    ...hook,
    functionName: "sharesOf",
    args: [poolKey[0], address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address, refetchInterval: 8000 },
  });

  const liquidity = liq ? parseUnits(liq, 18) : 0n;

  const approve = (token: `0x${string}`) =>
    writeContract({ address: token, abi: erc20Abi, functionName: "approve", args: [addresses.hook, maxUint256] });

  const deposit = () =>
    writeContract(
      {
        ...hook,
        functionName: "deposit",
        args: [poolKey[0], liquidity, maxUint256, maxUint256, address],
      },
      { onSuccess: () => setTimeout(() => refetch(), 2500) }
    );

  const withdrawAll = () =>
    writeContract(
      { ...hook, functionName: "withdraw", args: [poolKey[0], (shares as bigint) ?? 0n, 0n, 0n, address] },
      { onSuccess: () => setTimeout(() => refetch(), 2500) }
    );

  return (
    <div className="card">
      <h2>Your position</h2>
      <div className="stat">
        <span className="k">Vault shares</span>
        <span className="v">{fmt(shares as bigint, 18)}</span>
      </div>

      <div className="field">
        <input
          inputMode="decimal"
          placeholder="liquidity to add"
          value={liq}
          onChange={(e) => setLiq(e.target.value.replace(/[^0-9.]/g, ""))}
        />
        <button className="btn" disabled={!address || isPending || liquidity === 0n} onClick={deposit}>
          Deposit
        </button>
      </div>

      <div className="row" style={{ marginTop: 10 }}>
        <button className="btn ghost" disabled={!address} onClick={() => approve(addresses.token0)}>
          Approve {tokenMeta.token0.symbol}
        </button>
        <button className="btn ghost" disabled={!address} onClick={() => approve(addresses.token1)}>
          Approve {tokenMeta.token1.symbol}
        </button>
        <button
          className="btn ghost"
          disabled={!address || !shares || (shares as bigint) === 0n}
          onClick={withdrawAll}
          style={{ marginLeft: "auto" }}
        >
          Withdraw all
        </button>
      </div>

      <p className="note">
        Approve both tokens once, enter a liquidity amount, and deposit — the hook pulls the
        matching token amounts, mints your shares, and (if delta has moved enough) fires the
        first hedge. Withdraw burns shares and returns your tokens plus accrued LP fees.
      </p>
    </div>
  );
}
