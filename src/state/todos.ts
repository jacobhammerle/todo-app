/**
 * The task store: an in-memory list behind `useSyncExternalStore`. There is
 * no backend on purpose; the repo is about the workflows around the app.
 * Launch data comes from `src/state/seed.ts`.
 */
import { Observe } from "expo-observe";
import { useSyncExternalStore } from "react";

import { activePreset, buildSeedTodos, type SeedPreset } from "@/state/seed";

export type Priority = "low" | "medium" | "high";

export type Todo = {
  id: string;
  title: string;
  done: boolean;
  notes?: string;
  priority: Priority;
  /** Due date as a timestamp (ms). */
  dueAt?: number;
  /** When the task was checked, as a timestamp (ms). */
  completedAt?: number;
};

export type NewTodo = Pick<Todo, "title"> &
  Partial<Pick<Todo, "notes" | "priority" | "dueAt">>;

/** How many completed tasks the Tasks screen shows before linking to Done. */
const RECENT_DONE_LIMIT = 3;

let todos: Todo[] = buildSeedTodos();
let loadedPreset: SeedPreset = activePreset;
let nextId = 0;
const listeners = new Set<() => void>();

function emit() {
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function update(next: Todo[]) {
  todos = next;
  emit();
}

export function addTodo(input: NewTodo) {
  const title = input.title.trim();
  if (!title) return;
  const notes = input.notes?.trim();
  update([
    {
      // Time plus a counter, so two adds in one millisecond stay distinct.
      id: `${Date.now()}-${nextId++}`,
      title,
      done: false,
      notes: notes || undefined,
      priority: input.priority ?? "medium",
      dueAt: input.dueAt,
    },
    ...todos,
  ]);
  Observe.logEvent("todo.added", { attributes: { total: todos.length } });
}

/**
 * Checks or unchecks a task. Both screens call this, so the expo-observe
 * events live here: `todo.completed`, `todo.reopened`, and `todo.all_done`
 * when the last open task is checked.
 */
export function toggleTodo(id: string, done: boolean) {
  const openBefore = todos.filter((todo) => !todo.done).length;
  const target = todos.find((todo) => todo.id === id);
  if (!target || target.done === done) return;
  update(
    todos.map((todo) =>
      todo.id === id
        ? { ...todo, done, completedAt: done ? Date.now() : undefined }
        : todo,
    ),
  );
  Observe.logEvent(done ? "todo.completed" : "todo.reopened", {
    attributes: { id },
  });
  if (done && openBefore === 1) {
    Observe.logEvent("todo.all_done", { attributes: { total: todos.length } });
  }
}

/** Removes a single task for good. */
export function deleteTodo(id: string) {
  const target = todos.find((todo) => todo.id === id);
  if (!target) return;
  update(todos.filter((todo) => todo.id !== id));
  Observe.logEvent("todo.deleted", { attributes: { id } });
}

/** Removes every completed task for good. */
export function clearCompleted() {
  const count = todos.filter((todo) => todo.done).length;
  update(todos.filter((todo) => !todo.done));
  Observe.logEvent("todo.cleared", { attributes: { count } });
}

/** Replaces every task with a seed preset. See `src/state/seed.ts`. */
export function resetTodos(preset: SeedPreset = activePreset) {
  loadedPreset = preset;
  update(buildSeedTodos(preset));
  Observe.logEvent("admin.demo_data_loaded", { attributes: { preset } });
}

/** The seed preset most recently loaded (at launch or by `resetTodos`). */
export function useLoadedPreset() {
  return useSyncExternalStore(
    subscribe,
    () => loadedPreset,
    () => loadedPreset,
  );
}

export function useTodos() {
  const current = useSyncExternalStore(
    subscribe,
    () => todos,
    () => todos,
  );
  const active = current.filter((todo) => !todo.done);
  // Newest first, so the Tasks screen can show the most recent ones.
  const completed = current
    .filter((todo) => todo.done)
    .sort((a, b) => (b.completedAt ?? 0) - (a.completedAt ?? 0));
  const percent =
    current.length === 0
      ? 0
      : Math.round((completed.length / current.length) * 100);
  return {
    active,
    completed,
    recentlyDone: completed.slice(0, RECENT_DONE_LIMIT),
    total: current.length,
    percent,
  };
}
