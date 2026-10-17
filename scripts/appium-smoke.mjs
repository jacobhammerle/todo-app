// Appium smoke test against an EAS Simulator session.
//
// EAS Simulator can expose a plain Appium server for a session
// (`eas simulator:start --type appium`). This script is an ordinary
// WebdriverIO client: it launches the app, walks every bottom tab, checks
// one marker text per screen, and saves screenshots plus a report. Nothing
// here is EAS-specific except where the connection details come from.
//
// Run it (the session's binary is preinstalled with --build-id):
//   eas simulator:start --platform ios --type appium \
//     --build-id <ios simulator build id> --name "Appium smoke test" \
//     --max-duration-minutes 30 --non-interactive
//   eas simulator:exec node scripts/appium-smoke.mjs
//   eas simulator:stop
//
// `simulator:exec` loads APPIUM_URL and APPIUM_CAPS from .env.eas-simulator.
// The session page on expo.dev keeps the screen recording and the device
// metrics; this script writes its own artifacts to appium-artifacts/.
import { remote } from "webdriverio";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createRequire } from "node:module";

const appJson = createRequire(import.meta.url)("../app.json");
const BUNDLE_ID = appJson.expo.ios.bundleIdentifier;
const OUT_DIR = process.env.APPIUM_OUT_DIR || "appium-artifacts";

const url = process.env.APPIUM_URL;
const caps = process.env.APPIUM_CAPS;
if (!url || !caps) {
  console.error(
    "APPIUM_URL and APPIUM_CAPS are not set. Run through `eas simulator:exec`.",
  );
  process.exit(2);
}
const endpoint = new URL(url);

// Each tab, the marker text that proves its screen rendered, and the
// screenshot name.
const TABS = [
  { label: "Tasks", marker: "Add a task", shot: "1-tasks.png" },
  { label: "Done", marker: "Completed", shot: "2-done.png" },
  { label: "Admin", marker: "Channel", shot: "3-admin.png" },
];

mkdirSync(OUT_DIR, { recursive: true });
const report = {
  session: process.env.EAS_SIMULATOR_SESSION_ID ?? null,
  bundleId: BUNDLE_ID,
  steps: [],
};
const t0 = Date.now();
const log = (msg) =>
  console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s] ${msg}`);

const driver = await remote({
  protocol: endpoint.protocol.replace(":", ""),
  hostname: endpoint.hostname,
  port: Number(endpoint.port) || (endpoint.protocol === "https:" ? 443 : 80),
  path: endpoint.pathname === "/" ? "/" : endpoint.pathname,
  logLevel: "warn",
  connectionRetryTimeout: 180_000,
  capabilities: {
    ...JSON.parse(caps),
    "appium:bundleId": BUNDLE_ID,
    "appium:noReset": true,
    "appium:newCommandTimeout": 300,
  },
});
log(`Appium session ${driver.sessionId} on ${endpoint.hostname}`);

async function textVisible(text, timeout = 30_000) {
  // $$ not $: a marker can legitimately match several elements (a label and
  // its row), and $ treats that as an error.
  const selector = `-ios predicate string:label CONTAINS[c] "${text}" OR value CONTAINS[c] "${text}"`;
  await driver.waitUntil(async () => (await driver.$$(selector)).length > 0, {
    timeout,
    timeoutMsg: `"${text}" did not appear within ${timeout} ms`,
  });
}

async function tapTab(label) {
  // Native tab bar buttons carry the tab label as their accessibility name.
  const button = await driver.$(
    `-ios predicate string:type == "XCUIElementTypeButton" AND name == "${label}"`,
  );
  await button.waitForDisplayed({ timeout: 20_000 });
  await button.click();
}

let failed = 0;
try {
  for (const tab of TABS) {
    const step = {
      tab: tab.label,
      marker: tab.marker,
      status: "PASS",
      screenshot: tab.shot,
    };
    const started = Date.now();
    try {
      // Tap every tab, Tasks included: with noReset the app keeps whatever
      // tab the previous run left it on.
      await tapTab(tab.label);
      await textVisible(tab.marker);
      await driver.saveScreenshot(join(OUT_DIR, tab.shot));
      log(`PASS ${tab.label}: "${tab.marker}" is on screen`);
    } catch (error) {
      failed += 1;
      step.status = "FAIL";
      step.error = String(error.message ?? error).split("\n")[0];
      await driver.saveScreenshot(join(OUT_DIR, tab.shot)).catch(() => {});
      log(`FAIL ${tab.label}: ${step.error}`);
    }
    step.ms = Date.now() - started;
    report.steps.push(step);
  }
} finally {
  await driver.deleteSession().catch(() => {});
}

report.verdict = failed
  ? `FAIL: ${failed} of ${TABS.length} tabs failed`
  : `PASS: all ${TABS.length} tabs rendered`;
report.seconds = Math.round((Date.now() - t0) / 1000);
writeFileSync(
  join(OUT_DIR, "report.json"),
  JSON.stringify(report, null, 2) + "\n",
);
writeFileSync(
  join(OUT_DIR, "report.md"),
  [
    `# Appium smoke test`,
    ``,
    `**Verdict:** ${report.verdict} (${report.seconds} s)`,
    ``,
    `| Tab | Marker text | Result | Time |`,
    `| --- | --- | --- | --- |`,
    ...report.steps.map(
      (s) =>
        `| ${s.tab} | ${s.marker} | ${s.status}${s.error ? ` (${s.error})` : ""} | ${s.ms} ms |`,
    ),
    ``,
    `Screenshots: ${report.steps.map((s) => s.screenshot).join(", ")}`,
    ``,
  ].join("\n"),
);
log(report.verdict);
process.exit(failed ? 1 : 0);
