---
description: Which shell syntax to use when handing commands to the user vs writing script files.
---

# Shell: fish for inline, bash for script files

User's interactive login shell is **fish**. Default everywhere on this host.

## The rule

- **Inline commands the user runs** (copy-paste into their prompt, one-off ops,
  steps in an answer) → **fish syntax**. Bash-isms break when pasted into fish.
- **Script FILES** (committed `.sh`, complex logic, loops/traps/arrays) → **bash**
  is fine. Give it a `#!/usr/bin/env bash` shebang; the user executes the file, the
  shell parsing it is bash, not their interactive fish. Reach for a file when the
  logic is too gnarly for a clean fish one-liner.

## Bash → fish cheats (the ones that bite)

| bash | fish |
|---|---|
| `VAR=val` / `export VAR=val` | `set VAR val` / `set -x VAR val` |
| `$(cmd)` | `(cmd)` |
| `${v%.*}` (strip ext) | `string replace -r '\.[^.]+$' '' -- $v` (or `path change-extension '' $v`) |
| `while read -d '' x; do … done` | `while read -lz x … end` (`-z` null, `-l` local) |
| `[[ -f $f ]]` / `[[ $a == b ]]` | `test -f $f` / `test "$a" = b`; or `string match` |
| `arr=(a b)` / `${arr[@]}` | `set arr a b` / `$arr` |
| `for x in *.txt; do` | `for x in *.txt` … `end` (fish auto-globs; errors on no-match) |
| `cmd1 && cmd2` | `cmd1; and cmd2` (or `&&` works in fish 3.x too) |
| heredoc `<<EOF` | fish has none — use `printf`/`echo`, or write a script file |

- Fish auto-expands globs after a variable (`rm $base.*` works); no-match aborts
  the command (a guaranteed match avoids the error).
- Null-delimited `find -print0 | while read -lz` is the safe loop for paths with
  spaces/unicode (youtube/media filenames).
- When a one-liner needs heredocs, `trap`, complex arrays, or `set -euo pipefail`
  semantics → stop fighting fish, write a `#!/usr/bin/env bash` script file instead.

## Tool not installed → comma for one-off, systemPackages for recurring

Host has `,` (comma, from nix-index). Handing the user a command whose tool may
not be installed:

- **One-off / inspection** (`dmidecode`, `lshw`, `pciutils`, …) → `, <tool> <args>`
  runs it ephemerally from nixpkgs, no install. Prereq: the nix-index DB is
  populated (`nix-index` run at least once); stale/empty DB → comma can't find it.
- **Recurring** → add to `environment.systemPackages` (`modules/cli.nix`) instead;
  don't make the user comma the same tool every session. (`dmidecode` was promoted
  this way once it became a repeat need.)
- Don't tell the user "command not found" and stop — reach for `,` first, then
  decide if it earns a permanent spot.
