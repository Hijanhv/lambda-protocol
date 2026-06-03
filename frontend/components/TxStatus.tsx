"use client";

import { useWaitForTransactionReceipt } from "wagmi";
import { explorerUrl, hookChain } from "@/lib/config";

/**
 * Inline status for the panel's last write: confirming → confirmed (with an explorer
 * link), or a short error. Keeps a failed or pending transaction legible instead of the
 * button silently re-enabling. `hash` / `error` come straight from `useWriteContract`.
 */
export function TxStatus({ hash, error }: { hash?: `0x${string}`; error?: Error | null }) {
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({
    hash,
    chainId: hookChain.id,
    query: { enabled: !!hash },
  });

  if (error) {
    // viem errors carry a concise `shortMessage`; fall back to the full message.
    const msg = (error as { shortMessage?: string }).shortMessage ?? error.message;
    return (
      <div className="mt-2 font-sans text-[12px] leading-snug text-rose">
        {msg.length > 140 ? `${msg.slice(0, 140)}…` : msg}
      </div>
    );
  }

  if (!hash) return null;

  return (
    <div className="mt-2 flex items-center gap-1.5 font-sans text-[12px] text-muted">
      <span className={isSuccess ? "text-brand" : ""}>
        {isLoading ? "Confirming…" : isSuccess ? "Confirmed" : "Submitted"}
      </span>
      <span className="text-faint">·</span>
      <a
        href={`${explorerUrl}/tx/${hash}`}
        target="_blank"
        rel="noreferrer"
        className="text-brand underline-offset-2 hover:underline"
      >
        View on Uniscan <span className="text-faint">↗</span>
      </a>
    </div>
  );
}
