import { ListItem, Text } from "@expo/ui";
import { DatePickerDialog } from "@expo/ui/jetpack-compose";
import { useState } from "react";

import { BrandColor } from "@/constants/theme";
import { useTheme } from "@/hooks/use-theme";
import { formatDay } from "@/utils/time";

/** A "Due" row that opens the Material 3 date picker dialog. Keeps the time of day. */
export function DueDatePicker({
  value,
  onChange,
}: {
  value: Date;
  onChange: (date: Date) => void;
}) {
  const colors = useTheme();
  const [open, setOpen] = useState(false);

  return (
    <>
      <ListItem
        onPress={() => setOpen(true)}
        trailing={
          <Text textStyle={{ color: colors.tint }}>
            {formatDay(value.getTime())}
          </Text>
        }
      >
        <Text>Due</Text>
      </ListItem>
      {open ? (
        <DatePickerDialog
          initialDate={value.toISOString()}
          color={BrandColor}
          selectableDates={{ start: new Date() }}
          onDateSelected={(picked) => {
            const next = new Date(value);
            next.setFullYear(
              picked.getFullYear(),
              picked.getMonth(),
              picked.getDate(),
            );
            onChange(next);
            setOpen(false);
          }}
          onDismissRequest={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}
