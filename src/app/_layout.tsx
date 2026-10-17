import { Observe, ObserveRoot } from "expo-observe";
import { DarkTheme, DefaultTheme, ThemeProvider } from "expo-router";

import AppTabs from "@/components/app-tabs";
import { UpdateMonitor } from "@/components/update-monitor";
import { useColorScheme } from "@/hooks/use-color-scheme";

// EAS Observe: app metrics plus per-route timings through the router.
Observe.configure({
  integrations: { "expo-router": true },
});

function TabLayout() {
  const colorScheme = useColorScheme();
  return (
    <ThemeProvider value={colorScheme === "dark" ? DarkTheme : DefaultTheme}>
      <UpdateMonitor />
      <AppTabs />
    </ThemeProvider>
  );
}

export default ObserveRoot.wrap(TabLayout);
