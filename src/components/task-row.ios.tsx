import { ListItem, Text } from "@expo/ui";
import { Button, SwipeActions } from "@expo/ui/swift-ui";

import { TaskCheck } from "@/components/task-check";
import { useTheme } from "@/hooks/use-theme";
import type { Todo } from "@/state/todos";
import { formatDay } from "@/utils/time";

/** The one-line summary under a title: due date, priority, notes. */
function describe(todo: Todo) {
  return [
    todo.dueAt !== undefined ? `Due ${formatDay(todo.dueAt)}` : null,
    todo.priority === "high" ? "High priority" : null,
    todo.priority === "low" ? "Low priority" : null,
    todo.notes,
  ]
    .filter(Boolean)
    .join(" · ");
}

/**
 * A task row. Tapping the row or its check toggles the task.
 * `onDelete`, when provided, adds a swipe-to-delete action.
 */
export function TaskRow({
  todo,
  showDate = false,
  onToggle,
  onDelete,
}: {
  todo: Todo;
  showDate?: boolean;
  onToggle: (id: string, done: boolean) => void;
  onDelete?: (id: string) => void;
}) {
  const colors = useTheme();
  const toggle = () => onToggle(todo.id, !todo.done);
  const details = describe(todo);
  const row = (
    <ListItem
      onPress={toggle}
      leading={<TaskCheck done={todo.done} onToggle={toggle} />}
      supportingText={details || undefined}
      trailing={
        showDate && todo.completedAt !== undefined ? (
          <Text textStyle={{ fontSize: 15, color: colors.textSecondary }}>
            {formatDay(todo.completedAt)}
          </Text>
        ) : undefined
      }
    >
      <Text textStyle={todo.done ? { color: colors.textSecondary } : undefined}>
        {todo.title}
      </Text>
    </ListItem>
  );

  if (!onDelete) return row;

  return (
    <SwipeActions>
      {row}
      <SwipeActions.Actions>
        <Button
          role="destructive"
          label="Delete"
          onPress={() => onDelete(todo.id)}
        />
      </SwipeActions.Actions>
    </SwipeActions>
  );
}
