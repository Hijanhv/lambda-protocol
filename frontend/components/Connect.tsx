"use client";

import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect, type Connector } from "wagmi";
import { shortAddr } from "@/lib/format";

/**
 * Wallet picker. wagmi discovers each installed browser wallet separately
 * (EIP-6963), so we list one option per wallet — MetaMask, Uniswap Wallet, etc.
 * — instead of blindly grabbing connectors[0].
 */
export function Connect() {
  const { address, isConnected, connector } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const [open, setOpen] = useState(false);

  // Dedupe by name; drop the generic "Injected" fallback when named wallets exist.
  const seen = new Set<string>();
  const unique = connectors.filter((c) => {
    const key = c.name.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  const named = unique.filter((c) => c.id !== "injected");
  const wallets = named.length ? named : unique;

  // Close the menu once a connection lands.
  useEffect(() => {
    if (isConnected) setOpen(false);
  }, [isConnected]);

  if (isConnected) {
    return (
      <button className="btn btn-ghost group" onClick={() => disconnect()} title={`Connected with ${connector?.name}`}>
        {connector?.icon && <img src={connector.icon} alt="" className="h-4 w-4 rounded" />}
        <span className="h-1.5 w-1.5 rounded-full bg-brand" />
        <span className="font-mono text-[12.5px]">{shortAddr(address)}</span>
        <span className="text-faint transition-colors group-hover:text-ink">· Disconnect</span>
      </button>
    );
  }

  return (
    <div className="relative">
      <button className="btn" disabled={isPending} onClick={() => setOpen((v) => !v)}>
        {isPending ? "Connecting…" : "Connect Wallet"}
      </button>

      {open && (
        <>
          {/* click-away backdrop */}
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-50 mt-2 w-60 overflow-hidden rounded-xl border border-line bg-surface p-1.5 shadow-lift">
            <div className="px-2.5 py-1.5 font-sans text-[11px] font-bold uppercase tracking-[0.16em] text-faint">
              Choose a wallet
            </div>
            {wallets.length === 0 && (
              <div className="px-2.5 py-3 font-sans text-[13px] text-muted">
                No wallet detected. Install MetaMask or the Uniswap Wallet extension.
              </div>
            )}
            {wallets.map((c) => (
              <WalletRow key={c.uid} connector={c} onPick={() => connect({ connector: c })} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function WalletRow({ connector, onPick }: { connector: Connector; onPick: () => void }) {
  return (
    <button
      onClick={onPick}
      className="flex w-full items-center gap-3 rounded-lg px-2.5 py-2.5 text-left transition-colors hover:bg-surface2"
    >
      {connector.icon ? (
        <img src={connector.icon} alt="" className="h-6 w-6 rounded-md" />
      ) : (
        <span className="grid h-6 w-6 place-items-center rounded-md bg-surface2 font-display text-[13px] text-brand">
          {connector.name.charAt(0)}
        </span>
      )}
      <span className="font-sans text-[14px] font-medium text-ink">{connector.name}</span>
    </button>
  );
}
