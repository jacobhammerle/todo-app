/**
 * Generates the app icon set from a single SVG design.
 *
 * Outputs (in assets/images/):
 *   icon.png                          iOS/root icon, production (no badge)   1024
 *   icon-local.png                    iOS/root icon, LOCAL ribbon            1024
 *   icon-develop.png                  iOS/root icon, DEV ribbon              1024
 *   android-icon-background.png       adaptive-icon background (gradient)    1024
 *   android-icon-foreground.png       adaptive-icon foreground, production   1024
 *   android-icon-foreground-local.png                                        1024
 *   android-icon-foreground-develop.png                                      1024
 *   android-icon-monochrome.png       adaptive-icon monochrome (no badge)    1024
 *   splash-icon.png                   splash glyph on transparent            512
 *   favicon.png                       web favicon, rounded                   128
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

// Shared paints and filters. The background is a diagonal blue gradient
// with a soft highlight in the top-left and a gentle vignette at the
// bottom, so the icon reads as lit rather than flat.
const DEFS = `
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#5FB9FF"/>
    <stop offset="0.55" stop-color="#2A8BE8"/>
    <stop offset="1" stop-color="#0A4FA3"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.18" cy="0.10" r="0.95">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="vignette" cx="0.5" cy="1.05" r="0.9">
    <stop offset="0.45" stop-color="#001F45" stop-opacity="0"/>
    <stop offset="1" stop-color="#001F45" stop-opacity="0.35"/>
  </radialGradient>
  <linearGradient id="check" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#4ADE80"/>
    <stop offset="1" stop-color="#16A34A"/>
  </linearGradient>
  <linearGradient id="box" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#4FA9F7"/>
    <stop offset="1" stop-color="#1F78D8"/>
  </linearGradient>
  <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/>
    <stop offset="1" stop-color="#F2F7FC"/>
  </linearGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="170%">
    <feDropShadow dx="0" dy="26" stdDeviation="26" flood-color="#04244C" flood-opacity="0.38"/>
  </filter>
  <filter id="shadowSoft" x="-30%" y="-30%" width="160%" height="170%">
    <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#04244C" flood-opacity="0.22"/>
  </filter>`;

// Row geometry in 1024 space, shared by the colour glyph and the monochrome mask.
const ROWS = [
  { cy: 372, line: 300, done: false },
  { cy: 512, line: 220, done: false },
  { cy: 652, line: 260, done: true },
];
const BOX = { x: 304, size: 76, rx: 22, stroke: 16 };
const LINE = { x: 424, h: 30, rx: 15 };

function rowShapes({ colour }) {
  return ROWS.map(({ cy, line, done }) => {
    const bx = BOX.x;
    const by = cy - BOX.size / 2;
    const box = done
      ? colour
        ? `<rect x="${bx}" y="${by}" width="${BOX.size}" height="${BOX.size}" rx="${BOX.rx}" fill="url(#check)" filter="url(#shadowSoft)"/>
           <path d="M ${bx + 20} ${cy + 2} L ${bx + 33} ${cy + 15} L ${bx + 57} ${cy - 13}" fill="none" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>`
        : `<rect x="${bx}" y="${by}" width="${BOX.size}" height="${BOX.size}" rx="${BOX.rx}" fill="#000000"/>`
      : `<rect x="${bx + BOX.stroke / 2}" y="${by + BOX.stroke / 2}" width="${BOX.size - BOX.stroke}" height="${BOX.size - BOX.stroke}" rx="${BOX.rx - BOX.stroke / 2}" fill="none" stroke="${colour ? "url(#box)" : "#000000"}" stroke-width="${BOX.stroke}"/>`;
    const lineFill = colour ? (done ? "#D9E4F0" : "#C3D2E3") : "#000000";
    return `${box}
      <rect x="${LINE.x}" y="${cy - LINE.h / 2}" width="${line}" height="${LINE.h}" rx="${LINE.rx}" fill="${lineFill}"/>`;
  }).join("\n");
}

// The glyph: a second sheet tucked behind, then the front card with its
// shadow, then three rows with the last one ticked.
const CARD = { x: 212, y: 212, w: 600, h: 600, rx: 100 };
const GLYPH = `
  <g>
    <g transform="rotate(-8 512 512)">
      <rect x="${CARD.x + 8}" y="${CARD.y + 8}" width="${CARD.w - 16}" height="${CARD.h - 16}" rx="${CARD.rx - 8}"
        fill="#FFFFFF" fill-opacity="0.30"/>
    </g>
    <rect x="${CARD.x}" y="${CARD.y}" width="${CARD.w}" height="${CARD.h}" rx="${CARD.rx}" fill="url(#paper)" filter="url(#shadow)"/>
    ${rowShapes({ colour: true })}
  </g>`;

function ribbon(text) {
  if (!text) return "";
  return `
  <rect x="0" y="848" width="1024" height="176" fill="#082A4F"/>
  <text x="512" y="936" text-anchor="middle" dominant-baseline="central"
    font-family="${FONT}" font-size="120" font-weight="800" letter-spacing="14"
    fill="#FFFFFF">${text}</text>`;
}

function pill(text) {
  if (!text) return "";
  const width = text.length <= 3 ? 340 : 640;
  return `
  <rect x="${512 - width / 2}" y="760" width="${width}" height="150" rx="75" fill="#082A4F"/>
  <text x="512" y="835" text-anchor="middle" dominant-baseline="central"
    font-family="${FONT}" font-size="96" font-weight="800" letter-spacing="10"
    fill="#FFFFFF">${text}</text>`;
}

const svgHeader = (viewBox = `0 0 ${SIZE} ${SIZE}`) =>
  `<svg width="${SIZE}" height="${SIZE}" viewBox="${viewBox}" xmlns="http://www.w3.org/2000/svg">`;

const BACKGROUND = `
  <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>
  <rect width="${SIZE}" height="${SIZE}" fill="url(#glow)"/>
  <rect width="${SIZE}" height="${SIZE}" fill="url(#vignette)"/>`;

// Full-bleed icon for iOS / root: background + glyph + bottom ribbon.
function fullIcon(badgeText) {
  return `${svgHeader()}
    <defs>${DEFS}</defs>
    ${BACKGROUND}
    ${GLYPH}
    ${ribbon(badgeText)}
  </svg>`;
}

// Adaptive foreground: transparent, glyph (+ pill badge) scaled into the ~66% safe zone.
function adaptiveForeground(badgeText) {
  const scale = 0.58;
  const offset = (SIZE * (1 - scale)) / 2;
  const dy = badgeText ? -30 : 20;
  return `${svgHeader()}
    <defs>${DEFS}</defs>
    <g transform="translate(${offset}, ${offset + dy}) scale(${scale})">
      ${GLYPH}
      ${pill(badgeText)}
    </g>
  </svg>`;
}

// Adaptive background: just the lit gradient.
const adaptiveBackground = `${svgHeader()}
  <defs>${DEFS}</defs>
  ${BACKGROUND}
</svg>`;

// Monochrome: white alpha silhouette of the front card, rows cut out via mask.
const monochrome = `${svgHeader()}
  <defs>
    <mask id="cut">
      <rect width="${SIZE}" height="${SIZE}" fill="#FFFFFF"/>
      ${rowShapes({ colour: false })}
    </mask>
  </defs>
  <g transform="translate(215, 215) scale(0.58)" mask="url(#cut)">
    <rect x="${CARD.x}" y="${CARD.y}" width="${CARD.w}" height="${CARD.h}" rx="${CARD.rx}" fill="#FFFFFF"/>
  </g>
</svg>`;

// Splash: the glyph alone on transparent, cropped to the card plus its shadow.
const splash = `${svgHeader("132 132 760 760")}
  <defs>${DEFS}</defs>
  ${GLYPH}
</svg>`;

// Favicon: the full icon with rounded corners.
const favicon = `${svgHeader()}
  <defs>${DEFS}
    <clipPath id="round"><rect width="${SIZE}" height="${SIZE}" rx="224"/></clipPath>
  </defs>
  <g clip-path="url(#round)">
    ${BACKGROUND}
    ${GLYPH}
  </g>
</svg>`;

async function render(svg, filename, size = SIZE) {
  await sharp(Buffer.from(svg), { density: 144 })
    .resize(size, size)
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
await render(splash, "splash-icon.png", 512);
await render(favicon, "favicon.png", 128);

console.log("done");
