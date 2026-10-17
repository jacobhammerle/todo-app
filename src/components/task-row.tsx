import { ListItem, Text } from "@expo/ui";

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

/** A task row. Tapping the row or its check toggles the task. */
export function TaskRow({
  todo,
  showDate = false,
  onToggle,
}: {
  todo: Todo;
  showDate?: boolean;
  onToggle: (id: string, done: boolean) => void;
}) {
  const colors = useTheme();
  const toggle = () => onToggle(todo.id, !todo.done);
  const details = describe(todo);
  return (
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
}
