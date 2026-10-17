import { useSyncExternalStore } from "react";
import { useColorScheme as useRNColorScheme } from "react-native";

const emptySubscribe = () => () => {};

/**
 * On web the static export renders "light" on the server; the real scheme
 * applies after hydration so server and client markup match.
 */
export function useColorScheme() {
  const hasHydrated = useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false,
  );
  const colorScheme = useRNColorScheme();

  return hasHydrated ? colorScheme : "light";
}
