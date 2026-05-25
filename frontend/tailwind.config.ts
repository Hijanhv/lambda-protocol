import type { Config } from "tailwindcss";

/**
 * Lambda — warm-paper light theme. Cream canvas, ink text, a deep pine-green
 * brand (yield / money) with a gold "fortune" accent. Type set by next/font in
 * app/layout.tsx via CSS variables.
 */
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        canvas: "#faf8f2",
        surface: "#ffffff",
        surface2: "#f4f0e7",
        ink: { DEFAULT: "#191710", soft: "#403d33" },
        muted: "#6c6a5f",
        faint: "#9b988c",
        line: "#e9e4d6",
        brand: { DEFAULT: "#116149", dim: "#0c4838", bright: "#198063" },
        gold: { DEFAULT: "#b07f25", bright: "#d6a23f", soft: "#f1e6cb" },
        rose: "#b4452f",
      },
      fontFamily: {
        display: ["var(--font-display)", "Georgia", "serif"],
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      letterSpacing: { tightest: "-0.04em" },
      borderRadius: { xl2: "1.25rem" },
      maxWidth: { content: "68rem" },
      boxShadow: {
        card: "0 1px 2px rgba(25,23,16,0.04), 0 12px 32px -16px rgba(25,23,16,0.16)",
        lift: "0 2px 4px rgba(25,23,16,0.05), 0 24px 60px -24px rgba(17,97,73,0.22)",
        seal: "0 6px 18px -6px rgba(17,97,73,0.5)",
      },
      keyframes: {
        rise: {
          "0%": { opacity: "0", transform: "translateY(16px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        pulseSoft: {
          "0%,100%": { opacity: "0.5" },
          "50%": { opacity: "1" },
        },
        sheen: {
          "0%": { transform: "translateX(-130%)" },
          "100%": { transform: "translateX(240%)" },
        },
        floaty: {
          "0%,100%": { transform: "translateY(0)" },
          "50%": { transform: "translateY(-8px)" },
        },
      },
      animation: {
        rise: "rise 0.7s cubic-bezier(0.16,1,0.3,1) both",
        pulseSoft: "pulseSoft 2.6s ease-in-out infinite",
        sheen: "sheen 3s ease-in-out infinite",
        floaty: "floaty 6s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
