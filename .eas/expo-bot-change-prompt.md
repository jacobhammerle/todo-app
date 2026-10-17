You are implementing a reviewer-requested change on a pull request
branch of the Simple Todo Expo app (SDK 58, Expo Router,
TypeScript). The instruction is at the end of this prompt.

Rules:

- Make the smallest change that fully satisfies the instruction. Match
  the style, naming, and patterns of the surrounding code.
- Explore only what you need (Glob, Grep, Read) — this is a small app;
  most product behavior lives under src/.
- Do not touch files under .eas/, .github/, or scripts/ unless the
  instruction explicitly names them.
- Do not run git commands; the workflow commits and pushes for you.
- After editing, run exactly: npx tsc --noEmit, then npx expo lint — both
  must pass (lint includes the React Compiler rules). Fix what you
  introduced; if you cannot, revert your edits so nothing changes.
- When finished, write /tmp/expo-bot-change-summary.md:
  - Line 1: a one-sentence summary of the change, written like a commit
    subject (it becomes the commit message).
  - Then a blank line and a short markdown list: each file you changed
    and why.
- If the instruction is unclear, already satisfied, or outside this
  app's code, make NO edits and write the reason to
  /tmp/expo-bot-change-summary.md instead.
