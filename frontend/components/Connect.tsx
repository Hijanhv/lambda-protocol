"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";
import { shortAddr } from "@/lib/format";

export function Connect() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected) {
    return (
      <button className="btn btn-ghost group" onClick={() => disconnect()}>
        <span className="h-1.5 w-1.5 rounded-full bg-brand" />
        <span className="font-mono text-[12.5px]">{shortAddr(address)}</span>
        <span className="text-faint transition-colors group-hover:text-ink">· Disconnect</span>
      </button>
    );
  }
  const injected = connectors[0];
  return (
    <button
      className="btn"
      disabled={!injected || isPending}
      onClick={() => injected && connect({ connector: injected })}
    >
      {isPending ? "Connecting…" : "Connect Wallet"}
    </button>
  );
}
