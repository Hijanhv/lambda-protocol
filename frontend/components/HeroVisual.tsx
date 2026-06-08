import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

/**
 * Hero product-preview collage: floating, overlapping cards that show Lambda's
 * real loop: the LP position + delta band, the auto-hedge on Hyperliquid with a
 * funding sparkline, and the cross-chain route with a traveling pulse. Numbers
 * are illustrative (marked "preview"). Pure SVG + CSS, no client JS.
 */
export function HeroVisual() {
  return (
    <div className="relative mx-auto h-[440px] w-full max-w-[520px]">
      {/* soft brand glow behind the cards */}
      <div
        className="pointer-events-none absolute inset-8 rounded-[44px] opacity-70 blur-2xl"
        style={{ background: "radial-gradient(closest-side, rgba(181,39,111,0.20), transparent)" }}
      />

      {/* Card A: LP position + delta band */}
      <Card className="absolute left-0 top-4 z-10 w-[252px] animate-floaty p-4 shadow-lift [animation-duration:7s]">
        <div className="flex items-center justify-between">
          <span className="font-sans text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">
            LP position
          </span>
          <span className="font-mono text-[11px] text-faint">WETH / USDC</span>
        </div>
        <div className="mt-3 flex items-baseline justify-between">
          <span className="font-sans text-[13px] text-muted">Delta</span>
          <span className="font-mono text-[15px] font-semibold tabular-nums text-ink">+1.92 ETH</span>
        </div>
        <div className="relative mt-3 h-1.5 rounded-full bg-secondary">
          <div className="absolute inset-y-0 left-1/4 right-1/4 rounded-full bg-brand/15" />
          <div className="absolute left-[64%] top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-card bg-brand" />
        </div>
        <div className="mt-2 font-sans text-[10.5px] text-faint">tracked on-chain · exact, not approximate</div>
      </Card>

      {/* Card B: auto-hedge + funding sparkline */}
      <Card className="absolute right-0 top-[60px] z-20 w-[262px] animate-floaty p-4 shadow-lift [animation-duration:9s] [animation-delay:0.6s]">
        <div className="flex items-center justify-between">
          <span className="font-sans text-[11px] font-semibold uppercase tracking-[0.14em] text-muted">
            Auto-hedge · Hyperliquid
          </span>
          <Badge variant="brand" className="gap-1 px-1.5 py-0 text-[9px]">
            <span className="h-1 w-1 rounded-full bg-brand animate-pulseSoft" />
            LIVE
          </Badge>
        </div>
        <div className="mt-3 flex items-baseline justify-between">
          <span className="font-sans text-[13px] text-muted">Short ETH-PERP</span>
          <span className="font-mono text-[15px] font-semibold tabular-nums text-rose">−1.25 ETH</span>
        </div>

        <svg viewBox="0 0 230 56" className="mt-3 w-full" fill="none" preserveAspectRatio="none">
          <defs>
            <linearGradient id="lvspark" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#B5276F" stopOpacity="0.35" />
              <stop offset="1" stopColor="#B5276F" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d="M0,44 L28,40 L56,42 L84,30 L112,33 L140,20 L168,24 L196,10 L224,5 L224,56 L0,56 Z"
            fill="url(#lvspark)"
          />
          <polyline
            points="0,44 28,40 56,42 84,30 112,33 140,20 168,24 196,10 224,5"
            stroke="#B5276F"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            vectorEffect="non-scaling-stroke"
            className="animate-draw"
            style={{ strokeDasharray: 520, strokeDashoffset: 520, animationDelay: "0.7s" }}
          />
          <circle cx="224" cy="5" r="3" fill="#B5276F" className="animate-pulseSoft" />
        </svg>

        <div className="mt-1 flex items-baseline justify-between">
          <span className="font-sans text-[11px] text-muted">Funding · 30d</span>
          <span className="font-mono text-[14px] font-semibold tabular-nums text-brand">+$1,284</span>
        </div>
      </Card>

      {/* Card C: cross-chain route */}
      <Card className="absolute bottom-2 left-[46px] z-10 w-[404px] animate-floaty p-4 shadow-lift [animation-duration:8s] [animation-delay:0.3s]">
        <div className="flex items-center gap-2">
          <span className="font-mono text-[11px] font-semibold text-brand">HedgeRequested</span>
          <span className="font-sans text-[11px] text-faint">routed on-chain, no off-chain bot</span>
        </div>
        <div className="relative mt-3 h-8">
          <div className="absolute left-[12%] right-[12%] top-1/2 h-px -translate-y-1/2 bg-edge/30" />
          <span className="absolute top-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-brand shadow-[0_0_0_4px_rgba(181,39,111,0.18)] animate-flowX" />
          <div className="relative flex h-full items-center justify-between">
            {["Unichain", "Reactive", "Hyperliquid"].map((n) => (
              <span
                key={n}
                className="rounded-full border border-edge bg-card px-2.5 py-1 font-sans text-[11px] font-medium text-ink"
              >
                {n}
              </span>
            ))}
          </div>
        </div>
      </Card>
    </div>
  );
}
