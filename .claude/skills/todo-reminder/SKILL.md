---
name: todo-reminder
description: Use at the START of a session in the homelab repo, and whenever the user asks "what's pending / what's left / any todos", to surface unfinished durable tasks from todo.txt (the git-tracked todo.txt-format list at the repo root). Also use after completing a task that matches an open todo line, to offer marking it done. Keeps cross-session obligations (e.g. the Suwayomi restore) from being forgotten after context compaction.
---

# Durable todo reminder (todo.txt + tuxedo)

The repo root holds a **git-tracked `todo.txt`** in standard todo.txt format.
It is the durable memory for multi-session obligations — things that must
survive context compaction and a fresh session (e.g. "restore Suwayomi after
the container is up"). The `tuxedo` binary (home-manager) reads the same file;
`$TODO_FILE` points at it.

## todo.txt format (what to parse)

One task per line. Examples:

```
(A) 2026-06-19 Restore Suwayomi library +suwayomi @manga due:2026-06-22
x 2026-06-20 2026-06-19 Restore Suwayomi library +suwayomi @manga
```

- `x ` prefix  → **DONE** (line completed; first date after `x` = completion date).
- `(A)`–`(Z)`  → priority. `(A)` = do first.
- leading `YYYY-MM-DD` → creation date.
- `+project`   → project tag (e.g. `+suwayomi`).
- `@context`   → context tag (e.g. `@manga`, `@cleanup`).
- `due:YYYY-MM-DD` → deadline.

**Incomplete = any line NOT starting with `x `** (and not blank).

## When triggered

1. Read `todo.txt` at the repo root (`/home/homeserver/homelab/todo.txt`).
2. List the **incomplete** lines (skip `x `-prefixed and blank lines), highest
   priority first ((A) before (B) before unprioritized). Show due dates; flag any
   `due:` that is past today.
3. Remind the user concisely. Caveman ok per global style. Example:
   > Pending todo (2): (A) Restore Suwayomi from .tachibk; (B) verify restore.
4. If nothing incomplete → say "todo.txt clear" and stop. Do not nag.

## Marking done

Never silently edit the list. When the user confirms a task is finished (or you
just completed work that clearly matches an open line), OFFER to mark it:

- Preferred: `tuxedo do <n>` (n = line number from `tuxedo ls`).
- Or edit `todo.txt` directly: prefix the line with `x ` + today's date, e.g.
  `x 2026-06-20 2026-06-19 Restore Suwayomi library +suwayomi @manga`.

## Adding tasks

`tuxedo add "Do the thing +project @context due:YYYY-MM-DD"`, or append a
todo.txt-format line directly. Keep the creation date (`YYYY-MM-DD`) leading.

## Git

`todo.txt` is committed alongside config — changes (new tasks, completions) are
expected to be staged/committed like any other repo edit when the user commits.
Do not commit it on your own unless the user asks.
