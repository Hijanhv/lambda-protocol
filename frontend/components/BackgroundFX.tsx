import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Original, code-drawn crypto/yield motifs that drift behind the landing page.
 * Pure SVG + CSS, no images, no JS. Low-opacity, pointer-events-none, fixed for
 * a gentle parallax feel, and frozen under prefers-reduced-motion.
 */
export function BackgroundFX() {
  return (
    <div aria-hidden className="pointer-events-none fixed inset-0 z-0 overflow-hidden">
      {/* large faint depth shapes hugging the margins */}
      <Float cls="-left-12 top-[6%] text-brand/[0.05]" anim="animate-floaty" dur="12s">
        <Donut s={240} />
      </Float>
      <Float cls="-right-16 top-[38%] text-gold/[0.06]" anim="animate-drift" dur="24s">
        <Hex s={210} />
      </Float>
      <Float cls="left-[-3%] top-[82%] text-brand/[0.05]" anim="animate-drift" dur="20s" delay="2s">
        <Hex s={150} />
      </Float>

      {/* coins */}
      <Float cls="left-[6%] top-[15%] text-brand/[0.13]" anim="animate-floaty" dur="7s">
        <Coin sym="λ" />
      </Float>
      <Float cls="right-[7%] top-[11%] text-gold/[0.18]" anim="animate-floaty" dur="9s" delay="0.6s">
        <Coin sym="%" />
      </Float>
      <Float cls="left-[13%] top-[62%] text-gold/[0.14]" anim="animate-drift" dur="18s">
        <Coin sym="$" />
      </Float>
      <Float cls="right-[15%] top-[68%] text-brand/[0.13]" anim="animate-floaty" dur="8s" delay="1s">
        <Coin sym="λ" small />
      </Float>

      {/* candlesticks + rising sparklines (trading / yield) */}
      <Float cls="left-[3%] top-[41%] text-brand/[0.12]" anim="animate-floaty" dur="10s">
        <Candles />
      </Float>
      <Float cls="right-[5%] top-[82%] text-brand/[0.13]" anim="animate-drift" dur="15s">
        <Spark />
      </Float>
      <Float cls="left-[46%] top-[5%] text-gold/[0.11]" anim="animate-floaty" dur="9s" delay="0.4s">
        <Spark />
      </Float>

      {/* drifting yield tags */}
      <Float cls="left-[19%] top-[31%] text-brand/[0.13]" anim="animate-floaty" dur="8s" delay="0.3s">
        <Tag label="+11% APR" />
      </Float>
      <Float cls="right-[19%] top-[33%] text-gold/[0.16]" anim="animate-drift" dur="17s">
        <Tag label="funding ↑" />
      </Float>
      <Float cls="right-[27%] top-[88%] text-brand/[0.12]" anim="animate-floaty" dur="11s">
        <Tag label="σ²⁄8" />
      </Float>
      <Float cls="left-[33%] top-[75%] text-gold/[0.13]" anim="animate-drift" dur="19s" delay="1.4s">
        <Tag label="Δ-neutral" />
      </Float>
    </div>
  );
}

function Float({
  cls,
  anim,
  dur,
  delay,
  children,
}: {
  cls: string;
  anim: string;
  dur: string;
  delay?: string;
  children: ReactNode;
}) {
  return (
    <div
      className={cn("absolute will-change-transform motion-reduce:animate-none", anim, cls)}
      style={{ animationDuration: dur, animationDelay: delay }}
    >
      {children}
    </div>
  );
}

/* ── original SVG motifs (fill/stroke = currentColor, tinted by the wrapper) ── */

function Coin({ sym, small }: { sym: string; small?: boolean }) {
  const s = small ? 40 : 56;
  return (
    <svg width={s} height={s} viewBox="0 0 56 56" fill="none">
      <circle cx="28" cy="28" r="26" stroke="currentColor" strokeWidth="2" />
      <circle cx="28" cy="28" r="20" stroke="currentColor" strokeWidth="1" strokeDasharray="3 4" opacity="0.7" />
      <text
        x="28"
        y="36"
        textAnchor="middle"
        fontSize="22"
        fontWeight="700"
        fill="currentColor"
        fontFamily="Georgia, serif"
      >
        {sym}
      </text>
    </svg>
  );
}

function Candles() {
  return (
    <svg width="68" height="60" viewBox="0 0 68 60" fill="none" stroke="currentColor" strokeWidth="1.5">
      <line x1="11" y1="6" x2="11" y2="52" />
      <rect x="6" y="20" width="10" height="22" fill="currentColor" opacity="0.85" />
      <line x1="30" y1="12" x2="30" y2="50" />
      <rect x="25" y="16" width="10" height="16" fill="currentColor" opacity="0.5" />
      <line x1="49" y1="2" x2="49" y2="46" />
      <rect x="44" y="10" width="10" height="26" fill="currentColor" opacity="0.85" />
    </svg>
  );
}

function Spark() {
  return (
    <svg
      width="82"
      height="46"
      viewBox="0 0 82 46"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polyline points="3,40 16,31 28,34 41,20 54,25 67,9 79,5" />
      <polyline points="70,5 79,5 79,15" opacity="0.8" />
    </svg>
  );
}

function Hex({ s }: { s: number }) {
  return (
    <svg width={s} height={s} viewBox="0 0 100 100" fill="none" stroke="currentColor" strokeWidth="2">
      <polygon points="50,4 91,27 91,73 50,96 9,73 9,27" />
      <polygon points="50,22 75,36 75,64 50,78 25,64 25,36" opacity="0.45" />
    </svg>
  );
}

function Donut({ s }: { s: number }) {
  return (
    <svg width={s} height={s} viewBox="0 0 100 100" fill="none" stroke="currentColor">
      <circle cx="50" cy="50" r="40" strokeWidth="6" opacity="0.4" />
      <circle cx="50" cy="50" r="40" strokeWidth="6" strokeLinecap="round" strokeDasharray="150 110" />
    </svg>
  );
}

function Tag({ label }: { label: string }) {
  return (
    <span className="inline-flex items-center rounded-full border border-current px-3 py-1 font-mono text-[12px] font-semibold">
      {label}
    </span>
  );
}
