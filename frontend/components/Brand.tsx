import Link from "next/link";

/** The λ seal — a pine-green tile with a cream lambda. */
export function Seal({ size = 36 }: { size?: number }) {
  return (
    <span
      className="grid shrink-0 place-items-center rounded-xl bg-brand font-display font-bold leading-none text-canvas shadow-seal"
      style={{ width: size, height: size, fontSize: size * 0.56 }}
    >
      λ
    </span>
  );
}

/** Clickable wordmark used in the nav. */
export function Wordmark({ href = "/", sub }: { href?: string; sub?: string }) {
  return (
    <Link href={href} className="flex items-center gap-3">
      <Seal />
      <span className="leading-tight">
        <span className="block font-display text-[19px] font-semibold tracking-tightest text-ink">Lambda</span>
        {sub && (
          <span className="block font-sans text-[10.5px] uppercase tracking-[0.18em] text-faint">{sub}</span>
        )}
      </span>
    </Link>
  );
}
