import { Gauge } from "@expo/ui/swift-ui";
import { frame, gaugeStyle, tint } from "@expo/ui/swift-ui/modifiers";

import { BrandColor } from "@/constants/theme";

export function ProgressRing({
  value,
  size = 56,
}: {
  value: number;
  size?: number;
}) {
  return (
    <Gauge
      value={value}
      modifiers={[
        gaugeStyle("circularCapacity"),
        tint(BrandColor),
        frame({ width: size, height: size }),
      ]}
    />
  );
}
