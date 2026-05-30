import Link from "next/link";
import { Seal } from "@/components/Brand";

/**
 * Editorial multi-column footer matching the landing's bordered rhythm.
 * Server component — pure markup.
 */
export function SiteFooter() {
  return (
    <footer className="border-t border-edge">
      <div className="mx-auto max-w-content px-5 py-12 md:px-8">
        <div className="grid gap-10 sm:grid-cols-2 md:grid-cols-4">
          {/* Brand block */}
          <div className="md:col-span-1">
            <div className="flex items-center gap-3">
              <Seal size={28} />
              <span className="font-display text-[18px] font-semibold tracking-tightest text-ink">Lambda</span>
            </div>
            <p className="mt-3 font-sans text-[13px] leading-relaxed text-muted">
              The loss every LP pays, caught and turned into yield.
            </p>
          </div>

          <FooterCol
            title="Product"
            items={[
              ["App", "/app"],
              ["Docs", "/docs"],
              ["GitHub", "https://github.com/Hijanhv/lambda-protocol"],
            ]}
          />
          <FooterCol
            title="Stack"
            items={[
              ["Uniswap v4", "https://docs.uniswap.org/contracts/v4/overview"],
              ["Reactive Network", "https://dev.reactive.network/"],
              ["Hyperliquid", "https://hyperliquid.gitbook.io/"],
              ["Aave V3", "https://aave.com/"],
            ]}
          />
          <FooterCol
            title="On-chain"
            items={[
              ["Hook · Unichain Sepolia", "https://sepolia.uniscan.xyz/address/0x23C3da7CF53862Fd38640100D4FB764bE2d2cac0"],
              ["Funding · Unichain Sepolia", "https://sepolia.uniscan.xyz/address/0x9e9bCdC6B6596fE31e9A013e760E6B3dB89293F1"],
              ["Reactive · Lasna", "https://lasna.reactscan.net/"],
            ]}
          />
        </div>

        <div className="mt-10 flex flex-col items-start justify-between gap-3 border-t border-edge/30 pt-6 font-sans text-[12px] text-faint sm:flex-row sm:items-center">
          <span>© {new Date().getFullYear()} Lambda · UHI9</span>
          <span className="font-mono">λ/V = σ²⁄8 → funding yield</span>
        </div>
      </div>
    </footer>
  );
}

function FooterCol({ title, items }: { title: string; items: [string, string][] }) {
  return (
    <div>
      <div className="font-sans text-[11px] font-bold uppercase tracking-[0.18em] text-faint">{title}</div>
      <ul className="mt-3 space-y-2 font-sans text-[13.5px]">
        {items.map(([label, href]) => {
          const ext = href.startsWith("http");
          const cls = "text-ink-soft transition-colors hover:text-brand";
          return (
            <li key={label}>
              {ext ? (
                <a href={href} target="_blank" rel="noopener noreferrer" className={cls}>
                  {label} <span className="text-faint">↗</span>
                </a>
              ) : (
                <Link href={href} className={cls}>
                  {label}
                </Link>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
