---
name: herdr-project-session
description: "Herdr session persistence. Use when asked to create a Herdr session or create a project session."
---

# Herdr Project Session

1. Inspect `modules/home/herdr-sessions.nix` and preserve every unrelated dirty edit. **Done:** intended session hunk is isolated.
2. Add one entry to `sessions` with `name` and `dir`; default `harness` to Claude, use `harness = "pi";` when requested or appropriate, and add `repo` only for a cloneable remote. **Done:** entry matches requested project details.
3. Create a runtime `herdr workspace` for immediate use when needed, with its label exactly equal persisted `name`; persisted session service is source of truth. Matching labels prevent duplicates. After switch or service activation, managed lifecycle closes matching stale workspace, recreates it, and resumes latest agent conversation where harness supports it. **Done:** workspace label matches `name`; persisted entry exists; after service activation, exactly one freshly managed workspace exists and harness has resumed or started.
4. Run targeted Nix eval/build. Switch only on explicit request. **Done:** validation result recorded.
5. Stage or commit only intended session and skill changes when asked. **Done:** unrelated dirty edits remain untouched.
