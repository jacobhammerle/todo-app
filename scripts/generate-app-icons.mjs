/**
 * Generates the app icon set from a single SVG design.
 *
 * Outputs (all 1024x1024 PNG, in assets/images/):
 *   icon.png                          iOS/root icon, production (no badge)
 *   icon-local.png                    iOS/root icon, LOCAL ribbon
 *   icon-develop.png                  iOS/root icon, DEV ribbon
 *   android-icon-background.png       adaptive-icon background (gradient)
 *   android-icon-foreground.png       adaptive-icon foreground, production
 *   android-icon-foreground-local.png
 *   android-icon-foreground-develop.png
 *   android-icon-monochrome.png       adaptive-icon monochrome (no badge)
 *
 * Run: node scripts/generate-app-icons.mjs
 */
import sharp from "sharp";
import { Buffer } from "node:buffer";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const OUT_DIR = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "assets",
  "images",
);

const SIZE = 1024;
const FONT = `-apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif`;

const GRADIENT = `
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#45A5F7"/>
    <stop offset="1" stop-color="#0E63B8"/>
  </linearGradient>`;

// To-do list glyph, drawn in 1024 space (spans roughly x 232-792, y 232-792):
// a white card with three rows, the last one ticked.
const GLYPH = `
  <g>
    <!-- card -->
    <rect x="232" y="232" width="560" height="560" rx="56" fill="#FFFFFF"/>
    <!-- row 1: empty circle + line -->
    <circle cx="340" cy="372" r="34" fill="none" stroke="#2F97F4" stroke-width="18"/>
    <rect x="412" y="358" width="300" height="28" rx="14" fill="#C9D6E4"/>
    <!-- row 2: empty circle + line -->
    <circle cx="340" cy="512" r="34" fill="none" stroke="#2F97F4" stroke-width="18"/>
    <rect x="412" y="498" width="240" height="28" rx="14" fill="#C9D6E4"/>
    <!-- row 3: ticked circle + struck line -->
    <circle cx="340" cy="652" r="34" fill="#22C55E"/>
    <path d="M 322 652 L 335 665 L 360 638" fill="none" stroke="#FFFFFF" stroke-width="12"
      stroke-linecap="round" stroke-linejoin="round"/>
    <rect x="412" y="638" width="270" height="28" rx="14" fill="#E3ECF5"/>
  </g>`;

function ribbon(text) {
  if (!text) return "";
  return `
  <rect x="0" y="848" width="1024" height="176" fill="#0A2E52"/>
  <text x="512" y="936" text-anchor="middle" dominant-baseline="central"
    font-family="${FONT}" font-size="120" font-weight="800" letter-spacing="14"
    fill="#FFFFFF">${text}</text>`;
}

function pill(text) {
  if (!text) return "";
  const width = text.length <= 3 ? 340 : 640;
  return `
  <rect x="${512 - width / 2}" y="760" width="${width}" height="150" rx="75" fill="#0A2E52"/>
  <text x="512" y="835" text-anchor="middle" dominant-baseline="central"
    font-family="${FONT}" font-size="96" font-weight="800" letter-spacing="10"
    fill="#FFFFFF">${text}</text>`;
}

const svgHeader = `<svg width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}" xmlns="http://www.w3.org/2000/svg">`;

// Full-bleed icon for iOS / root: gradient background + glyph + bottom ribbon.
function fullIcon(badgeText) {
  return `${svgHeader}
    <defs>${GRADIENT}</defs>
    <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>
    ${GLYPH}
    ${ribbon(badgeText)}
  </svg>`;
}

// Adaptive foreground: transparent, glyph (+ pill badge) scaled into the ~66% safe zone.
function adaptiveForeground(badgeText) {
  const scale = 0.58;
  const offset = (SIZE * (1 - scale)) / 2;
  // Nudge up slightly when a badge pill extends the composition downward.
  const dy = badgeText ? -30 : 20;
  return `${svgHeader}
    <g transform="translate(${offset}, ${offset + dy}) scale(${scale})">
      ${GLYPH}
      ${pill(badgeText)}
    </g>
  </svg>`;
}

// Adaptive background: just the gradient.
const adaptiveBackground = `${svgHeader}
  <defs>${GRADIENT}</defs>
  <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>
</svg>`;

// Monochrome: white alpha silhouette of the card, rows cut out via mask.
const monochrome = `${svgHeader}
  <defs>
    <mask id="cut">
      <rect width="${SIZE}" height="${SIZE}" fill="#FFFFFF"/>
      <circle cx="340" cy="372" r="34" fill="none" stroke="#000000" stroke-width="18"/>
      <rect x="412" y="358" width="300" height="28" rx="14" fill="#000000"/>
      <circle cx="340" cy="512" r="34" fill="none" stroke="#000000" stroke-width="18"/>
      <rect x="412" y="498" width="240" height="28" rx="14" fill="#000000"/>
      <circle cx="340" cy="652" r="34" fill="#000000"/>
      <rect x="412" y="638" width="270" height="28" rx="14" fill="#000000"/>
    </mask>
  </defs>
  <g transform="translate(215, 215) scale(0.58)" mask="url(#cut)">
    <rect x="232" y="232" width="560" height="560" rx="56" fill="#FFFFFF"/>
  </g>
</svg>`;

async function render(svg, filename) {
  await sharp(Buffer.from(svg))
    .resize(SIZE, SIZE)
    .png()
    .toFile(path.join(OUT_DIR, filename));
  console.log("wrote", filename);
}

await mkdir(OUT_DIR, { recursive: true });

await render(fullIcon(null), "icon.png");
await render(fullIcon("LOCAL"), "icon-local.png");
await render(fullIcon("DEV"), "icon-develop.png");
await render(adaptiveBackground, "android-icon-background.png");
await render(adaptiveForeground(null), "android-icon-foreground.png");
await render(adaptiveForeground("LOCAL"), "android-icon-foreground-local.png");
await render(adaptiveForeground("DEV"), "android-icon-foreground-develop.png");
await render(monochrome, "android-icon-monochrome.png");

console.log("done");
