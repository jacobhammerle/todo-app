import {
  FieldGroup,
  Host,
  ListItem,
  Row,
  Text,
  TextInput,
  useNativeState,
} from "@expo/ui";
import { Observe, useObserve } from "expo-observe";
import {
  channel as buildChannel,
  checkForUpdateAsync,
  fetchUpdateAsync,
  isEnabled,
  reloadAsync,
  runtimeVersion,
  setUpdateRequestHeadersOverride,
  UpdateCheckResultNotAvailableReason,
  useUpdates,
} from "expo-updates";
import { useEffect, useState } from "react";
import { Alert, StyleSheet } from "react-native";

import { FormAction } from "@/components/form-action";
import {
  currentCriticalIndex,
  describeInstallation,
} from "@/components/update-monitor";
import { BrandColor, MonoFont } from "@/constants/theme";
import { useTheme } from "@/hooks/use-theme";
import { seedPresets, type SeedPreset } from "@/state/seed";
import { resetTodos, useLoadedPreset } from "@/state/todos";

/** The channels every build knows about; any other channel can be typed in. */
const channels = ["preview", "production"];

const presetLabels: Record<SeedPreset, string> = {
  default: "Default",
  fresh: "Fresh start",
  allDone: "All done",
  empty: "Empty",
};

function describeNoUpdateReason(
  channel: string,
  reason: UpdateCheckResultNotAvailableReason | undefined,
) {
  switch (reason) {
    case UpdateCheckResultNotAvailableReason.NO_UPDATE_AVAILABLE_ON_SERVER:
      return `${channel} has no update for runtime ${runtimeVersion}; this build already runs the newest code it can.`;
    case UpdateCheckResultNotAvailableReason.UPDATE_PREVIOUSLY_FAILED:
      return `The newest update on ${channel} failed to launch here before, so it is not retried.`;
    case UpdateCheckResultNotAvailableReason.UPDATE_REJECTED_BY_SELECTION_POLICY:
      return `The newest update on ${channel} does not match this runtime version.`;
    case UpdateCheckResultNotAvailableReason.ROLLBACK_NO_EMBEDDED:
    case UpdateCheckResultNotAvailableReason.ROLLBACK_REJECTED_BY_SELECTION_POLICY:
      return `${channel} was rolled back to its embedded build, which does not apply here.`;
    default:
      return `${channel} returned no new update.`;
  }
}

/**
 * Channel surfing: ask the server for the channel's newest update, install
 * it, and reload. A rollback directive (the demo reset) is fetched and
 * applied on the next launch.
 */
async function checkFetchAndReloadAsync(channel: string) {
  const update = await checkForUpdateAsync();

  if (update.isAvailable) {
    await fetchUpdateAsync();
    await reloadAsync();
    return;
  }

  if (update.isRollBackToEmbedded) {
    await fetchUpdateAsync();
    Alert.alert(
      `${channel} was reset to the embedded build`,
      "The rollback is downloaded and applies on the next launch.",
      [
        { text: "Not now", style: "cancel" },
        { text: "Reload now", onPress: () => reloadAsync() },
      ],
    );
    return;
  }

  Alert.alert(
    `Nothing new on ${channel}`,
    describeNoUpdateReason(channel, update.reason),
  );
}

/** Loads a seed preset from `src/state/seed.ts` into the task list. */
function DemoDataSection() {
  const loaded = useLoadedPreset();
  const colors = useTheme();

  const load = (preset: SeedPreset) => {
    const count = seedPresets[preset].length;
    Alert.alert(
      `Load "${presetLabels[preset]}"?`,
      `This replaces every task with the ${count} ${count === 1 ? "task" : "tasks"} in this preset.`,
      [
        { text: "Cancel", style: "cancel" },
        { text: "Load", onPress: () => resetTodos(preset) },
      ],
    );
  };

  return (
    <FieldGroup.Section title="Demo data">
      {(Object.keys(seedPresets) as SeedPreset[]).map((preset) => {
        const isLoaded = preset === loaded;
        const count = seedPresets[preset].length;
        return (
          <ListItem
            key={preset}
            supportingText={`${count} ${count === 1 ? "task" : "tasks"}`}
            trailing={
              isLoaded ? (
                <Text
                  textStyle={{
                    fontSize: 15,
                    fontWeight: "600",
                    color: colors.success,
                  }}
                >
                  Loaded
                </Text>
              ) : (
                <Text textStyle={{ color: colors.tint }}>Load</Text>
              )
            }
            onPress={() => load(preset)}
          >
            <Text>{presetLabels[preset]}</Text>
          </ListItem>
        );
      })}
      <FormAction label="Reset demo data" onPress={() => load(loaded)} />
      <FieldGroup.SectionFooter>
        <Text>
          Presets live in src/state/seed.ts. Edit that file to change the demo
          tasks, or load a preset here to reset the list mid-demo.
        </Text>
      </FieldGroup.SectionFooter>
    </FieldGroup.Section>
  );
}

export default function AdminScreen() {
  const { markInteractive } = useObserve();
  const { currentlyRunning } = useUpdates();
  const [switching, setSwitching] = useState(false);
  const typedChannel = useNativeState("");
  const colors = useTheme();
  const installation = describeInstallation(currentlyRunning);

  useEffect(() => {
    markInteractive();
  }, [markInteractive]);

  const runChannelAction = async (
    errorTitle: string,
    action: () => Promise<void>,
  ) => {
    if (switching) return;
    setSwitching(true);
    try {
      await action();
    } catch (error) {
      Alert.alert(errorTitle, String(error));
    } finally {
      setSwitching(false);
    }
  };

  const switchToChannel = (channel: string) =>
    runChannelAction("Channel switch failed", async () => {
      setUpdateRequestHeadersOverride({ "expo-channel-name": channel });
      await checkFetchAndReloadAsync(channel);
      Observe.logEvent("admin.channel_switched", { attributes: { channel } });
    });

  const resetToBuildChannel = () =>
    runChannelAction("Channel reset failed", async () => {
      setUpdateRequestHeadersOverride(null);
      await checkFetchAndReloadAsync(buildChannel ?? "none");
      Observe.logEvent("admin.channel_reset", {});
    });

  const confirmSwitch = (channel: string) => {
    if (channel === buildChannel) {
      Alert.alert(
        `Already on ${channel}`,
        "This build's own channel is active.",
      );
      return;
    }
    Alert.alert(
      `Switch to ${channel}?`,
      "The app downloads the channel's latest update and reloads.",
      [
        { text: "Cancel", style: "cancel" },
        { text: "Switch", onPress: () => switchToChannel(channel) },
      ],
    );
  };

  const switchToTypedChannel = () => {
    const channel = typedChannel.value.trim();
    if (!channel) return;
    confirmSwitch(channel);
  };

  // Development builds load JavaScript from Metro, so expo-updates is off
  // and channel surfing needs a release build. Demo data still works.
  if (!isEnabled) {
    return (
      <Host
        style={styles.host}
        seedColor={BrandColor}
        useViewportSizeMeasurement
      >
        <FieldGroup>
          <FieldGroup.Section title="Updates">
            <ListItem>
              <Text>
                Updates are disabled in this development build. Install a
                preview or production build to switch channels.
              </Text>
            </ListItem>
          </FieldGroup.Section>
          <DemoDataSection />
        </FieldGroup>
      </Host>
    );
  }

  return (
    <Host style={styles.host} seedColor={BrandColor} useViewportSizeMeasurement>
      <FieldGroup>
        <FieldGroup.Section title="This installation">
          <ListItem
            trailing={
              <Text
                textStyle={{
                  fontSize: 15,
                  fontWeight: "600",
                  color: colors.tint,
                  fontFamily: MonoFont,
                }}
              >
                {installation.channel}
              </Text>
            }
          >
            <Text>Channel</Text>
          </ListItem>
          <ListItem
            trailing={
              <Text textStyle={{ fontSize: 15, fontFamily: MonoFont }}>
                {installation.runtime}
              </Text>
            }
          >
            <Text>Runtime version</Text>
          </ListItem>
          <ListItem
            supportingText={
              <Text textStyle={{ fontSize: 13, fontFamily: MonoFont }}>
                {installation.update}
              </Text>
            }
          >
            <Text>Running update</Text>
          </ListItem>
          <ListItem
            trailing={
              <Text textStyle={{ fontSize: 15, fontFamily: MonoFont }}>
                {String(currentCriticalIndex(currentlyRunning))}
              </Text>
            }
          >
            <Text>Critical index</Text>
          </ListItem>
          <FieldGroup.SectionFooter>
            <Text>
              “embedded” means no update has been applied yet. The critical
              index is bumped by `npm run update:critical`; an update with a
              higher index installs itself at once instead of on the next
              launch.
            </Text>
          </FieldGroup.SectionFooter>
        </FieldGroup.Section>

        <FieldGroup.Section title="Update channel">
          {channels.map((channel) => {
            const isCurrent = channel === buildChannel;
            return (
              <ListItem
                key={channel}
                trailing={
                  isCurrent ? (
                    <Row spacing={8} alignment="center">
                      <Row
                        style={{
                          width: 8,
                          height: 8,
                          borderRadius: 4,
                          backgroundColor: colors.success,
                        }}
                      />
                      <Text
                        textStyle={{
                          fontSize: 15,
                          fontWeight: "600",
                          color: colors.success,
                        }}
                      >
                        Active
                      </Text>
                    </Row>
                  ) : (
                    <Text textStyle={{ color: colors.tint }}>
                      {switching ? "Switching…" : "Switch"}
                    </Text>
                  )
                }
                onPress={() => confirmSwitch(channel)}
              >
                <Text textStyle={{ fontSize: 15, fontFamily: MonoFont }}>
                  {channel}
                </Text>
              </ListItem>
            );
          })}
          <FieldGroup.SectionFooter>
            <Text>
              Switching downloads the latest compatible update from the selected
              channel and reloads the app. The selection persists until reset.
            </Text>
          </FieldGroup.SectionFooter>
        </FieldGroup.Section>

        <FieldGroup.Section title="Surf to any channel">
          <TextInput
            value={typedChannel}
            placeholder="channel name"
            autoCapitalize="none"
            autoCorrect={false}
            enterKeyHint="go"
            onSubmitEditing={switchToTypedChannel}
            textStyle={{ fontSize: 15, fontFamily: MonoFont }}
          />
          <FormAction
            label={switching ? "Switching…" : "Surf"}
            onPress={switchToTypedChannel}
          />
          <FieldGroup.SectionFooter>
            <Text>
              Type any channel with an update published for this runtime version
              — for example the channel a PR workflow publishes to.
            </Text>
          </FieldGroup.SectionFooter>
        </FieldGroup.Section>

        <FieldGroup.Section>
          <FormAction
            label="Reset to build channel"
            onPress={resetToBuildChannel}
          />
        </FieldGroup.Section>

        <DemoDataSection />
      </FieldGroup>
    </Host>
  );
}

const styles = StyleSheet.create({
  host: {
    flex: 1,
  },
});
