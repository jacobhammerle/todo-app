# Simple Todo

Read the versioned docs at https://docs.expo.dev/versions/v58.0.0/ before writing Expo code.

- The app is three Expo Router screens under `src/app/` (`index.tsx` Tasks, `done.tsx`, `admin.tsx`) on native tabs from `@expo/ui`. State lives in `src/state/todos.ts`; launch data and demo presets in `src/state/seed.ts`.
- Before you finish a change, run `npm run typecheck` and `npm run lint`. CI and the agent workflows run the same two commands.
- The point of the repo is the automation: EAS Workflows in `.eas/workflows/` run coding agents (the CLI is chosen in `scripts/agent/run-agent.sh`) whose prompts live in `.eas/*.md` (kept out of the YAML because EAS caps a workflow file at 16 kB) through the scripts in `scripts/agent/`. Keep prompts in step with the UI text in `src/`.
- `.agents/skills/` holds the argent skills vendored at the version pinned in `skills-lock.json`; `.claude/skills/` symlinks to them. Do not edit them or run `argent init` here.
- Use the argent MCP server for simulator work. Keep the app small; it exists to be driven by agents.
