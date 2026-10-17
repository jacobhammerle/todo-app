import { FieldGroup, Host, ListItem, Text } from "@expo/ui";
import { useObserve } from "expo-observe";
import { useEffect } from "react";
import { Alert, StyleSheet } from "react-native";

import { FormAction } from "@/components/form-action";
import { TaskRow } from "@/components/task-row";
import { BrandColor } from "@/constants/theme";
import { clearCompleted, toggleTodo, useTodos } from "@/state/todos";

export default function DoneScreen() {
  const { markInteractive } = useObserve();
  const { completed } = useTodos();

  useEffect(() => {
    markInteractive();
  }, [markInteractive]);

  const clear = () => {
    if (completed.length === 0) return;
    Alert.alert(
      "Clear history?",
      `This removes ${completed.length} completed ${completed.length === 1 ? "task" : "tasks"} for good.`,
      [
        { text: "Cancel", style: "cancel" },
        { text: "Clear", style: "destructive", onPress: clearCompleted },
      ],
    );
  };

  return (
    <Host style={styles.host} seedColor={BrandColor} useViewportSizeMeasurement>
      <FieldGroup>
        <FieldGroup.Section title="Completed">
          {completed.length === 0 ? (
            <ListItem>
              <Text>Nothing completed yet.</Text>
            </ListItem>
          ) : (
            completed.map((todo) => (
              <TaskRow
                key={todo.id}
                todo={todo}
                showDate
                onToggle={toggleTodo}
              />
            ))
          )}
          <FieldGroup.SectionFooter>
            <Text>
              Every task you check appears here, newest first. Uncheck one to
              move it back to To do.
            </Text>
          </FieldGroup.SectionFooter>
        </FieldGroup.Section>

        {completed.length > 0 ? (
          <FieldGroup.Section>
            <FormAction label="Clear history" destructive onPress={clear} />
            <FieldGroup.SectionFooter>
              <Text>Clearing history removes completed tasks for good.</Text>
            </FieldGroup.SectionFooter>
          </FieldGroup.Section>
        ) : null}
      </FieldGroup>
    </Host>
  );
}

const styles = StyleSheet.create({
  host: {
    flex: 1,
  },
});
