import { ListItem, Text } from "@expo/ui";

import { formatDay } from "@/utils/time";

/** Web fallback: shows the due date without an editor. */
export function DueDatePicker({
  value,
}: {
  value: Date;
  onChange: (date: Date) => void;
}) {
  return (
    <ListItem trailing={<Text>{formatDay(value.getTime())}</Text>}>
      <Text>Due</Text>
    </ListItem>
  );
}
