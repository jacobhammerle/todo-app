/**
 * Publishes a CRITICAL update: bumps `expo.extra.criticalIndex` in app.json,
 * then runs `eas update`. Running apps compare the incoming manifest's index
 * to their own and self-install when it is higher — see
 * src/components/update-monitor.tsx.
 *
 * Usage:
 *   npm run update:critical -- --channel preview --message "Hotfix: broken checkout"
 *
 * Defaults: --channel preview, --message "Critical update".
 * Remember to commit the app.json bump afterwards so future baselines carry it.
 */
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const argValue = (flag, fallback) => {
  const index = args.indexOf(flag);
  return index === -1 ? fallback : args[index + 1];
};

const channel = argValue("--channel", "preview");
const message = argValue("--message", "Critical update");

const appJsonUrl = new URL("../app.json", import.meta.url);
const appJson = JSON.parse(readFileSync(appJsonUrl, "utf8"));
appJson.expo.extra.criticalIndex = (appJson.expo.extra.criticalIndex ?? 0) + 1;
writeFileSync(appJsonUrl, JSON.stringify(appJson, null, 2) + "\n");
console.log(`criticalIndex bumped to ${appJson.expo.extra.criticalIndex}`);

const { status } = spawnSync(
  "npx",
  [
    "eas-cli",
    "update",
    "--channel",
    channel,
    "--environment",
    channel,
    "--message",
    message,
  ],
  { stdio: "inherit" },
);
process.exit(status ?? 1);
