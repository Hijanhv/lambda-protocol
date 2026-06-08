"use client";

import { useAccount, useSwitchChain } from "wagmi";
import { hookChain } from "@/lib/config";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

/**
 * True when a wallet is connected but on a different chain than the hook lives on.
 * Reads still work (they use the fixed RPC transport, not the wallet), but any write
 * would go to the wrong chain, so action buttons gate on this and the banner prompts
 * a switch.
 */
export function useWrongNetwork() {
  const { isConnected, chainId } = useAccount();
  return isConnected && chainId !== hookChain.id;
}

/** A prompt to switch the wallet to the hook's chain, shown only when it's needed. */
export function NetworkBanner() {
  const wrong = useWrongNetwork();
  const { switchChain, isPending } = useSwitchChain();

  if (!wrong) return null;

  return (
    <Card className="mb-6 animate-rise border-rose/40 bg-rose/[0.06]">
      <CardContent className="flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="text-[13.5px] leading-relaxed text-ink-soft">
          <span className="font-semibold text-rose">Wrong network.</span> Your wallet is on a
          different chain. Switch to <span className="font-semibold text-ink">{hookChain.name}</span>{" "}
          to deposit, claim, or withdraw; the dashboard readings below are already live.
        </div>
        <Button
          size="sm"
          className="shrink-0"
          disabled={isPending}
          onClick={() => switchChain({ chainId: hookChain.id })}
        >
          {isPending ? "Switching…" : `Switch to ${hookChain.name}`}
        </Button>
      </CardContent>
    </Card>
  );
}
