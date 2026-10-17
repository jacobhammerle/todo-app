import {
  BottomSheet,
  Button,
  Column,
  FieldGroup,
  ListItem,
  Picker,
  Row,
  Spacer,
  Switch,
  Text,
  TextInput,
  type TextInputRef,
} from "@expo/ui";
import { useRef, useState } from "react";

import { DueDatePicker } from "@/components/due-date-picker";
import type { NewTodo, Priority } from "@/state/todos";

function tomorrowAtNine() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  date.setHours(9, 0, 0, 0);
  return date;
}

/** Sheet for adding a task with notes, a priority, and a due date. */
export function NewTaskSheet({
  isPresented,
  onDismiss,
  onAdd,
}: {
  isPresented: boolean;
  onDismiss: () => void;
  onAdd: (input: NewTodo) => void;
}) {
  const titleInput = useRef<TextInputRef>(null);
  const notesInput = useRef<TextInputRef>(null);
  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [priority, setPriority] = useState<Priority>("medium");
  const [hasDue, setHasDue] = useState(false);
  const [due, setDue] = useState(tomorrowAtNine);

  const reset = () => {
    titleInput.current?.clear();
    notesInput.current?.clear();
    setTitle("");
    setNotes("");
    setPriority("medium");
    setHasDue(false);
    setDue(tomorrowAtNine());
  };

  const close = () => {
    reset();
    onDismiss();
  };

  const add = () => {
    if (!title.trim()) return;
    onAdd({
      title,
      notes,
      priority,
      dueAt: hasDue ? due.getTime() : undefined,
    });
    reset();
  };

  return (
    <BottomSheet
      isPresented={isPresented}
      onDismiss={close}
      snapPoints={["full"]}
      contentPadding={0}
    >
      <Column spacing={0}>
        <Row
          alignment="center"
          style={{ paddingHorizontal: 16, paddingTop: 16 }}
        >
          <Button variant="text" label="Cancel" onPress={close} />
          <Spacer flexible />
          <Text textStyle={{ fontSize: 17, fontWeight: "600" }}>New task</Text>
          <Spacer flexible />
          <Button
            variant="text"
            label="Add"
            onPress={add}
            disabled={!title.trim()}
          />
        </Row>

        <FieldGroup>
          <FieldGroup.Section>
            <TextInput
              ref={titleInput}
              onChangeText={setTitle}
              placeholder="Title"
              autoCapitalize="sentences"
              enterKeyHint="done"
            />
            <TextInput
              ref={notesInput}
              onChangeText={setNotes}
              placeholder="Notes"
              multiline
              numberOfLines={3}
            />
          </FieldGroup.Section>

          <FieldGroup.Section title="Details">
            <ListItem
              trailing={
                <Picker
                  selectedValue={priority}
                  onValueChange={(value) => setPriority(value as Priority)}
                >
                  <Picker.Item label="Low" value="low" />
                  <Picker.Item label="Medium" value="medium" />
                  <Picker.Item label="High" value="high" />
                </Picker>
              }
            >
              <Text>Priority</Text>
            </ListItem>
            <Switch label="Due date" value={hasDue} onValueChange={setHasDue} />
            {hasDue ? <DueDatePicker value={due} onChange={setDue} /> : null}
            <FieldGroup.SectionFooter>
              <Text>
                Notes, priority, and the due date show under the task in the
                list.
              </Text>
            </FieldGroup.SectionFooter>
          </FieldGroup.Section>
        </FieldGroup>
      </Column>
    </BottomSheet>
  );
}
