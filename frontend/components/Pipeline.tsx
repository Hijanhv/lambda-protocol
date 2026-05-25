const STAGES = [
  { label: "Connect", sub: "wallet" },
  { label: "Deposit", sub: "mint shares" },
  { label: "Hedge live", sub: "short opens" },
  { label: "Funding", sub: "accrues to you" },
];

/** The four-stage capital-flow rail. `step` is the current active index (0-3). */
export function Pipeline({ step }: { step: number }) {
  return (
    <div className="rounded-xl2 border border-line bg-surface p-5 shadow-card">
      <div className="flex items-stretch">
        {STAGES.map((s, i) => {
          const done = i < step;
          const active = i === step;
          return (
            <div key={s.label} className="flex flex-1 items-center">
              <div className="flex flex-col items-center gap-2 text-center">
                <span
                  className={[
                    "grid h-9 w-9 place-items-center rounded-full font-mono text-[13px] transition-colors",
                    done
                      ? "bg-brand text-canvas"
                      : active
                      ? "bg-gold text-canvas shadow-[0_0_0_5px_rgba(214,162,63,0.18)] animate-pulseSoft"
                      : "border border-line bg-surface2 text-faint",
                  ].join(" ")}
                >
                  {done ? "✓" : i + 1}
                </span>
                <div className="leading-tight">
                  <div className={`font-sans text-[12.5px] font-semibold ${active || done ? "text-ink" : "text-muted"}`}>
                    {s.label}
                  </div>
                  <div className="font-sans text-[10.5px] text-faint">{s.sub}</div>
                </div>
              </div>
              {i < STAGES.length - 1 && (
                <div className="relative mx-1 mb-6 h-px flex-1 overflow-hidden bg-line">
                  {done && <div className="absolute inset-0 bg-brand/50" />}
                  {active && (
                    <div className="absolute inset-y-0 left-0 w-1/3 animate-sheen bg-gradient-to-r from-transparent via-gold to-transparent" />
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
