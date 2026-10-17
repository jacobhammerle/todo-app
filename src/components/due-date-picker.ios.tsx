import { DatePicker } from "@expo/ui/swift-ui";

/** SwiftUI date and time picker, shown as a compact form row. */
export function DueDatePicker({
  value,
  onChange,
}: {
  value: Date;
  onChange: (date: Date) => void;
}) {
  return (
    <DatePicker
      title="Due"
      selection={value}
      displayedComponents={["date", "hourAndMinute"]}
      range={{ start: new Date() }}
      onDateChange={onChange}
    />
  );
}
