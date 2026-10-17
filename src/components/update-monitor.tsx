import Constants from "expo-constants";
import * as Updates from "expo-updates";
import { useEffect, useRef } from "react";
import { AppState, StyleSheet, Text, View } from "react-native";

import { BrandColor } from "@/constants/theme";

// Demo speed: a published update shows up within seconds. A production app
// would check far less often (or only on foreground).
const CHECK_INTERVAL_MS = 15_000;

// Critical-update pattern (see https://github.com/expo/UpdatesAPIDemo):
// publishing with `npm run update:critical` bumps `expo.extra.criticalIndex`,
// which rides along in the update manifest. When an available update carries a
// higher index than the running app, it is downloaded and launched immediately
// instead of waiting for the next cold start.

type ManifestWithExtra = {
  extra?: { expoClient?: { extra?: { criticalIndex?: number } } };
};

const criticalIndexOf = (manifest: unknown): number | undefined =>
  (manifest as ManifestWithExtra)?.extra?.expoClient?.extra?.criticalIndex;

/** What this installation runs, for the Tasks footer and the Admin rows. */
export function describeInstallation(
  currentlyRunning: Updates.CurrentlyRunningInfo,
) {
  return {
    channel: Updates.channel || "none",
    runtime: Updates.runtimeVersion || "unknown",
    update: currentlyRunning.isEmbeddedLaunch
      ? "embedded"
      : (currentlyRunning.updateId ?? "unknown"),
  };
}

/** The criticalIndex the app is currently running (embedded config as fallback). */
export function currentCriticalIndex(
  currentlyRunning: Updates.CurrentlyRunningInfo,
): number {
  return (
    criticalIndexOf(currentlyRunning.manifest) ??
    Constants.expoConfig?.extra?.criticalIndex ??
    0
  );
}

function isAvailableUpdateCritical({
  currentlyRunning,
  availableUpdate,
}: Pick<
  Updates.UseUpdatesReturnType,
  "currentlyRunning" | "availableUpdate"
>): boolean {
  const availableIndex = criticalIndexOf(availableUpdate?.manifest) ?? 0;
  return availableIndex > currentCriticalIndex(currentlyRunning);
}

/**
 * Mounted once in the root layout. Polls for updates and re-checks whenever
 * the app foregrounds. Critical updates self-install with a brief banner,
 * non-critical updates keep the default behavior (applied on next launch).
 */
export function UpdateMonitor() {
  const updatesSystem = Updates.useUpdates();
  const { isUpdateAvailable, isUpdatePending } = updatesSystem;
  const isCritical = isAvailableUpdateCritical(updatesSystem);
  const installing = useRef(false);

  useEffect(() => {
    if (!Updates.isEnabled) return;
    const check = () => Updates.checkForUpdateAsync().catch(() => {});
    check();
    const interval = setInterval(check, CHECK_INTERVAL_MS);
    const appState = AppState.addEventListener("change", (state) => {
      if (state === "active") check();
    });
    return () => {
      clearInterval(interval);
      appState.remove();
    };
  }, []);

  useEffect(() => {
    if (!isCritical || !isUpdateAvailable || installing.current) return;
    installing.current = true;
    (async () => {
      try {
        if (!isUpdatePending) await Updates.fetchUpdateAsync();
        await Updates.reloadAsync();
      } catch {
        // One attempt per update: the next poll that changes state retries.
        installing.current = false;
      }
    })();
  }, [isCritical, isUpdateAvailable, isUpdatePending]);

  if (!Updates.isEnabled || !isUpdateAvailable || !isCritical) return null;

  return (
    <View style={styles.banner}>
      <Text style={styles.bannerText}>Critical update — installing…</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    zIndex: 999,
    backgroundColor: BrandColor,
    paddingTop: 64,
    paddingBottom: 12,
    alignItems: "center",
  },
  bannerText: {
    color: "#FFFFFF",
    fontSize: 14,
    fontWeight: "600",
  },
});
