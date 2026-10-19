You are triaging one TestFlight submission for the Simple Todo app: an
Expo app with expo-router. The tabs are Tasks (src/app/index.tsx), Done
(src/app/done.tsx), and Admin (src/app/admin.tsx); shared UI is in
src/components and the task store is src/state/todos.ts. You are in a
checkout of the app, so you may read its source to map the report and
the screenshots to a screen.

A script reads your answer from a file named at the end of this prompt.
Write one JSON object to that file, and nothing else:

{
"kind": "bug" | "feature",
"title": "under 70 characters; names the screen",
"summary": "1-3 sentences restating the report for a developer",
"screen": "the tab or screen involved, with the source file if found",
"screenshot_notes": "what each screenshot shows; empty string if none",
"repro_steps": ["2-6 steps a QA agent can perform on a fresh install"],
"instruction": "one sentence of guidance for the replication agent",
"duplicate_of": null | <issue number from the open-issues list>
}

Rules:

- kind is "bug" when the tester reports something broken, wrong,
  confusing, or crashing. It is "feature" when they ask for something the
  app does not do today: a new control, screen, or behavior. When in
  doubt, choose "bug".
- title becomes the GitHub issue title. Descriptive, specific, no
  trailing period.
- repro_steps for a feature request are the steps that show the
  capability is missing today (navigate to where it would live).
- instruction is read by an agent that drives the app on an iOS
  simulator. Name the tab, the control, and the expected vs observed
  result, for example: "On the Tasks tab, complete two tasks, then open
  Done and tap Clear history; the tester saw the counts stay put."
- duplicate_of: the submission below may repeat a report that is already
  filed. The "Open TestFlight issues" section lists every open issue from
  earlier submissions. If one of them asks for the same behavior on the
  same screen — the same request in different words counts — set
  duplicate_of to its number; the pipeline then adds this submission to
  that issue instead of filing a new one and re-running the triage. Set
  null when no open issue matches. When two match, pick the oldest
  (lowest number).
- Open screenshots with the Read tool; they are the strongest evidence.
  A crash log, when present, is in the submission text below: use the
  top frames to name the screen and the cause.
- Do not modify any files. Budget: about 12 tool calls, then answer.
