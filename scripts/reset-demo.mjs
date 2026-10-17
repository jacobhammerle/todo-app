/**
 * Resets one or all channels to a clean demo baseline, then restores
 * `expo.extra.criticalIndex` in app.json to the committed value so the
 * working tree is clean for the next `npm run update:critical`.
 *
 * Two modes:
 *   rollback (default) — publishes a roll-back-to-embedded directive so
 *     devices return to the update embedded in their build. The baseline is
 *     whatever JS each installed build embeds, so it varies by build age.
 *   --publish — publishes the current checkout's JS as a real update to the
 *     channel. Every device lands on the same fixed baseline regardless of
 *     which build it runs. Use this to fix a channel that serves stale JS.
 *
 * Usage:
 *   npm run demo:reset -- --channel preview --message "Demo reset"
 *   npm run demo:reset -- --all
 *   npm run demo:reset -- --all --publish --message "Baseline"
 *
 * Defaults: --channel preview, mode rollback, --message "Demo reset".
 */
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const ALL_CHANNELS = ["preview", "production"];

const args = process.argv.slice(2);
const argValue = (flag, fallback) => {
  const index = args.indexOf(flag);
  return index === -1 ? fallback : args[index + 1];
};

const channels = args.includes("--all")
  ? ALL_CHANNELS
  : [argValue("--channel", "preview")];
const publishMode = args.includes("--publish");
const message = argValue(
  "--message",
  publishMode ? "Demo baseline" : "Demo reset",
);

const appJsonUrl = new URL("../app.json", import.meta.url);

// --runtime-version is required by roll-back-to-embedded in non-interactive
// mode. runtimeVersion is derived in app.config.ts, not stored in app.json,
// so evaluate the real config with `expo config`. The `appVersion` policy
// maps to `version`, a literal string is used as-is; anything else
// (e.g. fingerprint) must be passed explicitly.
const resolveRuntimeVersion = () => {
  const explicit = argValue("--runtime-version", undefined);
  if (explicit) return explicit;
  const cfg = spawnSync("npx", ["expo", "config", "--json"], {
    encoding: "utf8",
  });
  if (cfg.status === 0) {
    const out = cfg.stdout;
    const config = JSON.parse(out.slice(out.indexOf("{")));
    if (typeof config.runtimeVersion === "string") return config.runtimeVersion;
    if (config.runtimeVersion?.policy === "appVersion") return config.version;
  }
  console.error(
    "Cannot resolve the runtime version from `expo config`; pass --runtime-version explicitly.",
  );
  process.exit(1);
};
// Only the rollback command needs it; skip the config evaluation otherwise.
const runtimeVersion = publishMode ? null : resolveRuntimeVersion();

for (const channel of channels) {
  console.log(
    `\n── Resetting ${channel} (${publishMode ? "publish baseline" : "roll back to embedded"}) ──`,
  );
  const command = publishMode
    ? [
        "eas-cli",
        "update",
        "--channel",
        channel,
        // Channel names match EAS environment names in this project.
        "--environment",
        channel,
        "--message",
        message,
        "--non-interactive",
      ]
    : [
        "eas-cli",
        "update:roll-back-to-embedded",
        "--channel",
        channel,
        "--message",
        message,
        "--runtime-version",
        runtimeVersion,
        "--non-interactive",
      ];
  const { status } = spawnSync("npx", command, { stdio: "inherit" });
  if (status !== 0) process.exit(status ?? 1);

  // Verify: the branch's newest update should now be the expected baseline.
  const list = spawnSync(
    "npx",
    ["eas-cli", "update:list", "--branch", channel, "--limit", "3", "--json"],
    { encoding: "utf8" },
  );
  if (list.status !== 0) {
    console.warn(`Could not verify branch ${channel}; check the dashboard.`);
    continue;
  }
  const updates = JSON.parse(list.stdout).currentPage ?? [];
  const [latest] = updates;
  // update:list --json decorates message with quotes and a byline, e.g.
  // `"Demo baseline" (just now by <username>)` — match by containment.
  const ok = publishMode
    ? latest && !latest.isRollBackToEmbedded && latest.message.includes(message)
    : latest?.isRollBackToEmbedded;
  console.log(
    ok
      ? publishMode
        ? `✔ ${channel} is serving the fresh baseline update (runtime ${latest.runtimeVersion})`
        : `✔ ${channel} is serving the embedded update (runtime ${latest.runtimeVersion})`
      : `✖ ${channel} latest update is NOT the expected baseline — check the dashboard`,
  );
  for (const update of updates) {
    const marker = update.isRollBackToEmbedded ? "↩" : "•";
    console.log(`  ${marker} ${update.message} [${update.runtimeVersion}]`);
  }
}

const committed = spawnSync("git", ["show", "HEAD:app.json"], {
  encoding: "utf8",
});
if (committed.status === 0) {
  const baselineIndex =
    JSON.parse(committed.stdout).expo.extra.criticalIndex ?? 0;
  const appJson = JSON.parse(readFileSync(appJsonUrl, "utf8"));
  if (appJson.expo.extra.criticalIndex !== baselineIndex) {
    appJson.expo.extra.criticalIndex = baselineIndex;
    writeFileSync(appJsonUrl, JSON.stringify(appJson, null, 2) + "\n");
    console.log(`\ncriticalIndex restored to ${baselineIndex}`);
  }
}

console.log(
  publishMode
    ? `\nNext step: relaunch the app on your test devices — the baseline update downloads and applies on next launch.`
    : `\nNext step: relaunch the app on your test devices — the rollback applies on next launch, not via the critical-update banner.`,
);
