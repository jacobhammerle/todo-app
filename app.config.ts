import type { ConfigContext, ExpoConfig } from "expo/config";

/** Derive runtime version from major.minor (patch is for OTA updates). */
function runtimeVersion(version: string): string {
  const [major, minor] = version.split(".");
  return `${major}.${minor}.0`;
}

type Variant = "local" | "develop" | "production";
const variant = (process.env.APP_VARIANT ?? "local") as Variant;

const iconsByVariant: Record<
  Variant,
  { icon: string; androidForeground: string }
> = {
  local: {
    icon: "./assets/images/icon-local.png",
    androidForeground: "./assets/images/android-icon-foreground-local.png",
  },
  develop: {
    icon: "./assets/images/icon-develop.png",
    androidForeground: "./assets/images/android-icon-foreground-develop.png",
  },
  production: {
    icon: "./assets/images/icon.png",
    androidForeground: "./assets/images/android-icon-foreground.png",
  },
};

export default ({ config }: ConfigContext): ExpoConfig => {
  const { icon, androidForeground } =
    iconsByVariant[variant] ?? iconsByVariant.local;
  return {
    ...(config as ExpoConfig),
    icon,
    android: {
      ...config.android,
      adaptiveIcon: {
        ...config.android?.adaptiveIcon,
        foregroundImage: androidForeground,
      },
    },
    runtimeVersion: runtimeVersion(config.version!),
  };
};
