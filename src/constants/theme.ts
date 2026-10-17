// The web build reads `--font-mono` from this stylesheet (see MonoFont).
import "@/global.css";

import { Platform } from "react-native";

// Values from the Expo design system tokens (fg-*, bg-*, brand-blue, status-*).
export const Colors = {
  light: {
    text: "#11181c",
    background: "#ffffff",
    backgroundElement: "#f5f5f7",
    backgroundSelected: "#eaecf0",
    textSecondary: "#596068",
    tint: "#0072de",
    success: "rgb(9,141,72)",
    danger: "rgb(207,34,46)",
  },
  dark: {
    text: "#e6edf3",
    background: "#0b0f14",
    backgroundElement: "#161a20",
    backgroundSelected: "#252932",
    textSecondary: "#9aa4ae",
    tint: "#4aa8ff",
    success: "#4ade80",
    danger: "#ff7a7a",
  },
} as const;

export type ThemeColor = keyof typeof Colors.light & keyof typeof Colors.dark;

export const MonoFont = Platform.select({
  ios: "ui-monospace",
  web: "var(--font-mono)",
  default: "monospace",
});

export const Spacing = {
  one: 4,
  two: 8,
  three: 16,
  five: 32,
} as const;

export const MaxContentWidth = 800;

/**
 * Expo design system `brand-blue`, used for native controls that take one
 * color. Text uses `useTheme().tint`, which adapts to dark mode. The app
 * icon and splash use a lighter blue (#208AEF) so the white glyph reads;
 * see scripts/generate-app-icons.mjs and app.json.
 */
export const BrandColor = "#0072de";
