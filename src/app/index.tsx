import {
  Column,
  FieldGroup,
  Host,
  ListItem,
  Text,
  TextInput,
  type TextInputRef,
} from "@expo/ui";
import { useRouter } from "expo-router";
import { useObserve } from "expo-observe";
import * as Updates from "expo-updates";
import { useEffect, useRef, useState } from "react";
import { StyleSheet } from "react-native";

import { FormAction } from "@/components/form-action";
import { NewTaskSheet } from "@/components/new-task-sheet";
import { ProgressRing } from "@/components/progress-indicators";
import { TaskRow } from "@/components/task-row";
import { describeInstallation } from "@/components/update-monitor";
import { BrandColor, MonoFont } from "@/constants/theme";
import { useTheme } from "@/hooks/use-theme";
import { addTodo, deleteTodo, toggleTodo, useTodos } from "@/state/todos";

export default function TasksScreen() {
  const { markInteractive } = useObserve();
  const router = useRouter();
  const colors = useTheme();
  const { active, completed, recentlyDone, total, percent } = useTodos();
  const { currentlyRunning } = Updates.useUpdates();
  const titleInput = useRef<TextInputRef>(null);
  const [title, setTitle] = useState("");
  const [sheetOpen, setSheetOpen] = useState(false);

  useEffect(() => {
    markInteractive();
  }, [markInteractive]);

  const submit = () => {
    const trimmed = title.trim();
    if (!trimmed) return;
    addTodo({ title: trimmed });
    titleInput.current?.clear();
    setTitle("");
  };

  // One line of EAS facts at the bottom of the list, so a screenshot shows
  // which channel and update produced it.
  const installation = describeInstallation(currentlyRunning);
  const easLine = Updates.isEnabled
    ? `${installation.channel} · runtime ${installation.runtime} · update ${installation.update.slice(0, 8)}`
    : "dev · updates disabled";

  return (
    <Host style={styles.host} seedColor={BrandColor} useViewportSizeMeasurement>
      <FieldGroup>
        <FieldGroup.Section>
          <ListItem
            leading={
              <ProgressRing
                value={total === 0 ? 0 : completed.length / total}
              />
            }
            supportingText={`${completed.length} of ${total} tasks done`}
            trailing={
              <Text
                textStyle={{
                  fontSize: 22,
                  fontWeight: "700",
                  color: colors.tint,
                }}
              >{`${percent}%`}</Text>
            }
          >
            <Text textStyle={{ fontSize: 17, fontWeight: "600" }}>
              {active.length === 0
                ? "All caught up"
                : `${active.length} ${active.length === 1 ? "task" : "tasks"} to do`}
            </Text>
          </ListItem>
        </FieldGroup.Section>

        <FieldGroup.Section title="Add a task">
          <TextInput
            ref={titleInput}
            onChangeText={setTitle}
            placeholder="What needs doing?"
            autoCapitalize="sentences"
            enterKeyHint="done"
            onSubmitEditing={submit}
          />
          <FormAction
            label="Add task"
            onPress={submit}
            disabled={!title.trim()}
          />
          <FormAction
            label="Add with details…"
            onPress={() => setSheetOpen(true)}
          />
        </FieldGroup.Section>

        <FieldGroup.Section title="To do">
          {active.length === 0 ? (
            <ListItem>
              <Text>Nothing left to do.</Text>
            </ListItem>
          ) : (
            active.map((todo) => (
              <TaskRow
                key={todo.id}
                todo={todo}
                onToggle={toggleTodo}
                onDelete={deleteTodo}
              />
            ))
          )}
          {completed.length === 0 ? (
            <FieldGroup.SectionFooter>
              <Text textStyle={{ fontSize: 12, fontFamily: MonoFont }}>
                {easLine}
              </Text>
            </FieldGroup.SectionFooter>
          ) : null}
        </FieldGroup.Section>

        {completed.length > 0 ? (
          <FieldGroup.Section title="Recently done">
            {recentlyDone.map((todo) => (
              <TaskRow key={todo.id} todo={todo} onToggle={toggleTodo} />
            ))}
            <FormAction
              label={`See all ${completed.length} in Done →`}
              onPress={() => router.navigate("/done")}
            />
            <FieldGroup.SectionFooter>
              <Column alignment="start" spacing={8}>
                <Text>Tap a done task to move it back to To do.</Text>
                <Text textStyle={{ fontSize: 12, fontFamily: MonoFont }}>
                  {easLine}
                </Text>
              </Column>
            </FieldGroup.SectionFooter>
          </FieldGroup.Section>
        ) : null}
      </FieldGroup>

      <NewTaskSheet
        isPresented={sheetOpen}
        onDismiss={() => setSheetOpen(false)}
        onAdd={(input) => {
          addTodo(input);
          setSheetOpen(false);
        }}
      />
    </Host>
  );
}

const styles = StyleSheet.create({
  host: {
    flex: 1,
  },
});
