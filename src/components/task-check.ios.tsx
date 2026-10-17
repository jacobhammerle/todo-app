import { Icon } from "@expo/ui";

import { useTheme } from "@/hooks/use-theme";

/**
 * SwiftUI has no checkbox toggle style on iOS (the universal `Checkbox` draws a
 * switch), so iOS uses the Reminders-style SF Symbol circle. The row handles taps.
 */
export function TaskCheck({ done }: { done: boolean; onToggle: () => void }) {
  const colors = useTheme();
  return (
    <Icon
      name={done ? "checkmark.circle.fill" : "circle"}
      size={22}
      color={done ? colors.tint : colors.textSecondary}
    />
  );
}
