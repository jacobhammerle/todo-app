/**
 * Demo seed data.
 *
 * This is the only file to edit to change what the app shows on launch.
 * Each preset is a plain list of tasks. Times are relative to "now", so the
 * demo looks fresh on any day:
 *
 *   { title: "Buy groceries" }                       → an open task
 *   { title: "Pay the rent", doneAgo: "1h" }         → done one hour ago
 *   { title: "File taxes", dueIn: "3d", priority: "high", notes: "…" }
 *
 * Durations: "30m", "2h", "3d", "1w". `dueIn` also accepts "-1d" (overdue).
 *
 * Pick which preset loads at launch with `activePreset`, or switch presets
 * live from the Admin tab ("Demo data" section).
 */

import type { Priority, Todo } from "@/state/todos";
import { DAY_MS, HOUR_MS, MINUTE_MS, WEEK_MS } from "@/utils/time";

export type SeedTask = {
  title: string;
  /** How long ago the task was completed. Omit for an open task. */
  doneAgo?: Duration;
  /** When the task is due, relative to now. Negative values are overdue. */
  dueIn?: Duration;
  priority?: Priority;
  notes?: string;
};

/** A number followed by m (minutes), h (hours), d (days), or w (weeks). */
export type Duration = `${"" | "-"}${number}${"m" | "h" | "d" | "w"}`;

export const seedPresets = {
  /** The everyday demo: a few open tasks and a short history. */
  default: [
    { title: "Buy groceries", dueIn: "1d", priority: "high" },
    { title: "Call the dentist", notes: "Ask about the Thursday slot" },
    { title: "Water the plants" },
    { title: "Pay the rent", doneAgo: "1h" },
    { title: "Book an oil change", doneAgo: "1d" },
    { title: "Return library books", doneAgo: "3d" },
    { title: "Copy spare keys", doneAgo: "5d" },
  ],
  /** A fresh start: nothing done yet. */
  fresh: [
    { title: "Buy groceries" },
    { title: "Call the dentist" },
    { title: "Water the plants" },
  ],
  /** Everything checked off: shows the "All caught up" state. */
  allDone: [
    { title: "Buy groceries", doneAgo: "10m" },
    { title: "Call the dentist", doneAgo: "2h" },
    { title: "Water the plants", doneAgo: "1d" },
  ],
  /** No tasks at all: shows the empty states. */
  empty: [],
} satisfies Record<string, SeedTask[]>;

export type SeedPreset = keyof typeof seedPresets;

/** The preset the app loads at launch. */
export const activePreset: SeedPreset = "default";

const UNIT_MS = { m: MINUTE_MS, h: HOUR_MS, d: DAY_MS, w: WEEK_MS } as const;

function durationToMs(duration: Duration): number {
  const match = /^(-?\d+(?:\.\d+)?)([mhdw])$/.exec(duration);
  if (!match) throw new Error(`Bad seed duration: "${duration}"`);
  const [, amount, unit] = match;
  return Number(amount) * UNIT_MS[unit as keyof typeof UNIT_MS];
}

function slug(title: string) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

/** Turns a preset into todos with stable ids and absolute timestamps. */
export function buildSeedTodos(preset: SeedPreset = activePreset): Todo[] {
  const now = Date.now();
  const seen = new Map<string, number>();
  return seedPresets[preset].map((task: SeedTask) => {
    const base = slug(task.title) || "task";
    const count = (seen.get(base) ?? 0) + 1;
    seen.set(base, count);
    const completedAt =
      task.doneAgo === undefined ? undefined : now - durationToMs(task.doneAgo);
    return {
      id: count === 1 ? base : `${base}-${count}`,
      title: task.title,
      done: completedAt !== undefined,
      notes: task.notes,
      priority: task.priority ?? "medium",
      dueAt:
        task.dueIn === undefined ? undefined : now + durationToMs(task.dueIn),
      completedAt,
    };
  });
}
