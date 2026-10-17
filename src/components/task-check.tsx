import { Checkbox } from "@expo/ui";

/** Material checkbox on Android, native checkbox on web. */
export function TaskCheck({
  done,
  onToggle,
}: {
  done: boolean;
  onToggle: () => void;
}) {
  return <Checkbox value={done} onValueChange={onToggle} />;
}
