Test the Tasks tab. One toggle only:

1. The app launches on the Tasks tab. Note the summary card's starting
   values: "N tasks to do", "X of Y tasks done", and the percent
   (round(X/Y*100)).
2. Complete ONE task under "To do": tap the CheckBox element at the
   leading (left) edge of its row (describe lists it as its own
   element). Verify the task leaves the "To do" list, the done count
   increases by one, and the percent updates to match. If nothing
   changed, re-run describe and tap the row's label text once; then
   judge again.

Out of scope for this lane — do NOT touch these:

- The Done tab. The round trip (uncheck on Done, back on Tasks) is
  tested on iOS only; this lane checks the first toggle.
- The "Add a task" field and the "Add task" row.
- The Admin tab.

Pass condition: the task leaves "To do" and the summary card's done
count and percent both advance by exactly one task.
