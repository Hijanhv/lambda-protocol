import type { Config } from "tailwindcss";

/**
 * Lambda — warm-paper light theme. Cream canvas, ink text, a deep pine-green
 * brand (yield / money) with a gold "fortune" accent. Type set by next/font in
 * app/layout.tsx via CSS variables.
 */
const config: Config = {
  darkMode: ["class"],
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        canvas: "#faf8f2",
        surface: "#ffffff",
        surface2: "#f4f0e7",
        ink: { DEFAULT: "#191710", soft: "#403d33" },
        muted: { DEFAULT: "#6c6a5f", foreground: "hsl(var(--muted-foreground))" },
        faint: "#9b988c",
        line: "#e9e4d6",
        brand: { DEFAULT: "#B5276F", dim: "#931E5A", bright: "#D24B92" },
        gold: { DEFAULT: "#b07f25", bright: "#d6a23f", soft: "#f1e6cb" },
        rose: "#b4452f",
        // crisp near-black hairline for the bordered editorial layout
        edge: "#211d14",
        // shadcn semantic tokens — CSS variables defined in app/globals.css
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: { DEFAULT: "hsl(var(--primary))", foreground: "hsl(var(--primary-foreground))" },
        secondary: { DEFAULT: "hsl(var(--secondary))", foreground: "hsl(var(--secondary-foreground))" },
        destructive: { DEFAULT: "hsl(var(--destructive))", foreground: "hsl(var(--destructive-foreground))" },
        accent: { DEFAULT: "hsl(var(--accent))", foreground: "hsl(var(--accent-foreground))" },
        popover: { DEFAULT: "hsl(var(--popover))", foreground: "hsl(var(--popover-foreground))" },
        card: { DEFAULT: "hsl(var(--card))", foreground: "hsl(var(--card-foreground))" },
      },
      fontFamily: {
        display: ["var(--font-display)", "Georgia", "serif"],
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      letterSpacing: { tightest: "-0.04em" },
      borderRadius: {
        xl2: "1.25rem",
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      maxWidth: { content: "68rem" },
      boxShadow: {
        card: "0 1px 2px rgba(25,23,16,0.04), 0 12px 32px -16px rgba(25,23,16,0.16)",
        lift: "0 2px 4px rgba(25,23,16,0.05), 0 24px 60px -24px rgba(181,39,111,0.22)",
        seal: "0 6px 18px -6px rgba(181,39,111,0.5)",
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
        // seamless marquee: track holds two identical copies, shift one copy width
        marquee: {
          "0%": { transform: "translateX(0)" },
          "100%": { transform: "translateX(-50%)" },
        },
        spinSlow: {
          "0%": { transform: "rotate(0deg)" },
          "100%": { transform: "rotate(360deg)" },
        },
        drift: {
          "0%,100%": { transform: "translate3d(0,0,0) rotate(0deg)" },
          "50%": { transform: "translate3d(14px,-26px,0) rotate(7deg)" },
        },
        draw: {
          to: { strokeDashoffset: "0" },
        },
        flowX: {
          "0%": { left: "0%", opacity: "0" },
          "12%": { opacity: "1" },
          "88%": { opacity: "1" },
          "100%": { left: "100%", opacity: "0" },
        },
      },
      animation: {
        rise: "rise 0.7s cubic-bezier(0.16,1,0.3,1) both",
        pulseSoft: "pulseSoft 2.6s ease-in-out infinite",
        sheen: "sheen 3s ease-in-out infinite",
        floaty: "floaty 6s ease-in-out infinite",
        marquee: "marquee 34s linear infinite",
        spinSlow: "spinSlow 7s linear infinite",
        drift: "drift 16s ease-in-out infinite",
        draw: "draw 2.2s ease-out forwards",
        flowX: "flowX 3.4s ease-in-out infinite",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};

export default config;
