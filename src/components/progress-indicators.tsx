import { View } from "react-native";

/**
 * Web fallback: a static ring. The web build is a convenience, not a demo
 * target, so it does not draw the progress value.
 */
export function ProgressRing({ size = 56 }: { value: number; size?: number }) {
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        borderWidth: 5,
        borderColor: "rgba(120,120,128,.16)",
      }}
    />
  );
}
