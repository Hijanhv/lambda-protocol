"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";
import { shortAddr } from "@/lib/format";

export function Connect() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected) {
    return (
      <button className="btn ghost" onClick={() => disconnect()}>
        {shortAddr(address)} · Disconnect
      </button>
    );
  }
  const injected = connectors[0];
  return (
    <button className="btn" disabled={!injected || isPending} onClick={() => injected && connect({ connector: injected })}>
      {isPending ? "Connecting…" : "Connect Wallet"}
    </button>
  );
}
