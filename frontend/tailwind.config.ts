import type { Config } from "tailwindcss";

/**
 * "Ledger of Fortune" — Ebisu (god of prosperity / fishermen) reimagined for a
 * Uniswap-v4 LP desk. Ink-black canvas, koi-gold actions, jade income, a
 * vermilion seal. Type set by next/font in app/layout.tsx via CSS variables.
 */
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: {
          950: "#08090c",
          900: "#0c0d12",
          850: "#111219",
          800: "#161821",
          700: "#1d202b",
          600: "#262a37",
        },
        gold: {
          DEFAULT: "#e3ad48",
          bright: "#f4cc6e",
          dim: "#a9802f",
        },
        jade: { DEFAULT: "#5cd0a0", dim: "#2f8c66" },
        vermilion: { DEFAULT: "#e2533b", dim: "#a83822" },
        paper: "#ece8dd",
        muted: "#8b8d99",
        faint: "#5a5d6b",
      },
      fontFamily: {
        display: ["var(--font-display)", "Georgia", "serif"],
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      letterSpacing: { tightest: "-0.04em" },
      borderRadius: { xl2: "1.25rem" },
      boxShadow: {
        lift: "0 1px 0 0 rgba(255,255,255,0.04) inset, 0 24px 60px -28px rgba(0,0,0,0.9)",
        seal: "0 0 0 1px rgba(226,83,59,0.4), 0 8px 24px -8px rgba(226,83,59,0.5)",
      },
      keyframes: {
        rise: {
          "0%": { opacity: "0", transform: "translateY(14px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        flow: {
          "0%": { offsetDistance: "0%", opacity: "0" },
          "12%": { opacity: "1" },
          "88%": { opacity: "1" },
          "100%": { offsetDistance: "100%", opacity: "0" },
        },
        pulseSoft: {
          "0%,100%": { opacity: "0.55" },
          "50%": { opacity: "1" },
        },
        sheen: {
          "0%": { transform: "translateX(-120%)" },
          "100%": { transform: "translateX(220%)" },
        },
      },
      animation: {
        rise: "rise 0.7s cubic-bezier(0.16,1,0.3,1) both",
        flow: "flow 3.2s linear infinite",
        pulseSoft: "pulseSoft 2.6s ease-in-out infinite",
        sheen: "sheen 2.8s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
