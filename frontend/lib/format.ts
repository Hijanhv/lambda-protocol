import { formatUnits } from "viem";

/** Human-readable token amount with a fixed number of significant decimals. */
export function fmt(value: bigint | undefined, decimals: number, places = 4): string {
  if (value === undefined) return "—";
  const s = formatUnits(value, decimals);
  const n = Number(s);
  if (n === 0) return "0";
  if (n < 0.0001) return "<0.0001";
  return n.toLocaleString(undefined, { maximumFractionDigits: places });
}

/** Short address form 0x1234…abcd. */
export function shortAddr(a?: string): string {
  if (!a) return "—";
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

/** A pips fee (1e-6) as a percent string, e.g. 3000 → "0.30%". */
export function feePctFromPips(pips: bigint | undefined): string {
  if (pips === undefined) return "—";
  return `${(Number(pips) / 10_000).toFixed(2)}%`;
}
