import { ListItem, Text } from "@expo/ui";

import { useTheme } from "@/hooks/use-theme";

/** A full-width action row inside a FieldGroup, styled like a native button. */
export function FormAction({
  label,
  onPress,
  destructive = false,
}: {
  label: string;
  onPress: () => void;
  destructive?: boolean;
}) {
  const colors = useTheme();
  return (
    <ListItem onPress={onPress}>
      <Text
        textStyle={{
          color: destructive ? colors.danger : colors.tint,
          fontWeight: "600",
        }}
      >
        {label}
      </Text>
    </ListItem>
  );
}
