import { CircularProgressIndicator } from "@expo/ui/jetpack-compose";

import { BrandColor } from "@/constants/theme";

/** Material 3 circular indicator. Compose picks the size, so `size` is ignored. */
export function ProgressRing({ value }: { value: number; size?: number }) {
  return <CircularProgressIndicator progress={value} color={BrandColor} />;
}
