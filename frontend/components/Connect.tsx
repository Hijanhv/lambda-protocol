"use client";

import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect, type Connector } from "wagmi";
import { shortAddr } from "@/lib/format";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/**
 * Wallet picker. wagmi discovers each installed browser wallet separately
 * (EIP-6963), so we list one option per wallet (MetaMask, Uniswap Wallet, etc.)
 * instead of blindly grabbing connectors[0]. Built on shadcn DropdownMenu so we
 * inherit keyboard nav, focus management, and click-away handling from Radix.
 *
 * SSR note: wagmi reports `isConnected: false` during render-on-server (no
 * wallet there). If a wallet auto-reconnects on the client, the markup flips
 * from plain "Connect Wallet" to the address-pill variant, which has spans
 * inside the button and triggers a React hydration mismatch. We gate on a
 * `mounted` flag so SSR + first client render always agree, then flip on
 * mount.
 */
export function Connect() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const { address, isConnected, connector } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  // Wallets we don't offer.
  const EXCLUDED = ["phantom"];

  // Dedupe by name; drop excluded wallets and the generic "Injected" fallback when named wallets exist.
  const seen = new Set<string>();
  const unique = connectors.filter((c) => {
    const key = c.name.toLowerCase();
    if (seen.has(key)) return false;
    if (EXCLUDED.some((x) => key.includes(x))) return false;
    seen.add(key);
    return true;
  });
  const named = unique.filter((c) => c.id !== "injected");
  const wallets = named.length ? named : unique;

  // Before hydration: render the plain disconnected button so SSR and the first
  // client render produce identical DOM. After mount, switch to the real state.
  if (!mounted) {
    return (
      <Button size="sm" disabled>
        Connect Wallet
      </Button>
    );
  }

  // Connected: address pill that opens an action menu.
  if (isConnected) {
    return (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="sm" title={`Connected with ${connector?.name}`}>
            {connector?.icon && <img src={connector.icon} alt="" className="h-4 w-4 rounded" />}
            <span className="h-1.5 w-1.5 rounded-full bg-brand" />
            <span className="font-mono text-[12.5px] tabular-nums">{shortAddr(address)}</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel>Wallet</DropdownMenuLabel>
          <DropdownMenuItem asChild>
            <a
              href={`https://sepolia.uniscan.xyz/address/${address}`}
              target="_blank"
              rel="noopener noreferrer"
              className="cursor-pointer"
            >
              View on Uniscan <span className="ml-auto text-faint">↗</span>
            </a>
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() => {
              if (address) navigator.clipboard?.writeText(address);
            }}
          >
            Copy address
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => disconnect()} className="text-rose focus:text-rose">
            Disconnect
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    );
  }

  // Disconnected: connect button that opens the wallet list.
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button size="sm" disabled={isPending}>
          {isPending ? "Connecting…" : "Connect Wallet"}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuLabel>Choose a wallet</DropdownMenuLabel>
        {wallets.length === 0 ? (
          <div className="px-2.5 py-3 font-sans text-[13px] text-muted">
            No wallet detected. Install MetaMask or the Uniswap Wallet extension.
          </div>
        ) : (
          wallets.map((c) => (
            <WalletRow key={c.uid} connector={c} onPick={() => connect({ connector: c })} />
          ))
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function WalletRow({ connector, onPick }: { connector: Connector; onPick: () => void }) {
  return (
    <DropdownMenuItem onSelect={onPick}>
      {connector.icon ? (
        <img src={connector.icon} alt="" className="h-6 w-6 rounded-md" />
      ) : (
        <span className="grid h-6 w-6 place-items-center rounded-md bg-secondary font-display text-[13px] text-brand">
          {connector.name.charAt(0)}
        </span>
      )}
      <span className="font-sans text-[14px] font-medium text-ink">{connector.name}</span>
    </DropdownMenuItem>
  );
}
