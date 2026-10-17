/** Millisecond units, shared by the seed data and the date labels. */
export const MINUTE_MS = 60 * 1000;
export const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;
export const WEEK_MS = 7 * DAY_MS;

/** "Today", "Yesterday", "Tomorrow", or a short date such as "Oct 14". */
export function formatDay(timestamp: number) {
  const day = new Date(timestamp);
  const today = new Date();
  const startOf = (d: Date) =>
    new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const diffDays = Math.round((startOf(today) - startOf(day)) / DAY_MS);
  if (diffDays === 0) return "Today";
  if (diffDays === 1) return "Yesterday";
  if (diffDays === -1) return "Tomorrow";
  return day.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
