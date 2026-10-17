Test the Tasks tab. One round trip only:

1. The app launches on the Tasks tab. Note the summary card's starting
   values: "N tasks to do", "X of Y tasks done", and the percent
   (round(X/Y*100)).
2. Complete ONE task under "To do": tap the control the UI pitfalls name
   for this platform (iOS: anywhere on the row; Android: the CheckBox
   element at the leading edge, or the row). Verify the task leaves the
   "To do" list, the done count increases by one, and the percent
   updates to match.
3. Open the Done tab. Verify the task is listed under "Completed".
   Uncheck it. Open the Tasks tab again and verify the summary card is
   back to the starting values and the task is back under "To do".

Out of scope for this lane — do NOT touch these:

- The "Add a task" field and the "Add task" row.
- The "Clear history" row. Do not tap it, and do not report on it.
- The Admin tab.

Pass condition: the summary card tracks both toggles correctly and ends
at the starting values.
