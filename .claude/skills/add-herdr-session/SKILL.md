---
name: add-herdr-session
description: Add a new durable herdr coding session (workspace + agent pane) to this homelab. Use when the user wants to "add/create a new herdr session", "bikin session herdr baru", spin up a persistent claude or pi coding workspace, or disable/comment an existing session. Covers the declarative nix entry in modules/home/herdr-sessions.nix, the project dir + git init, optional GitHub repo, and the rebuild that provisions it. NOT for controlling a running herdr (panes/splits/live agents) — that is the global `herdr` skill.
---

# Add a herdr session

Durable herdr sessions are **declarative**: one entry in the `sessions` list in
`modules/home/herdr-sessions.nix`. A oneshot provisioner
(`herdr-sessions.service`) creates the workspace + agent pane on the next
`herdr-server` (re)start; `nixos-rebuild switch` triggers that.

Read the top-of-file comment in `modules/home/herdr-sessions.nix` before editing
— it documents the durability layers and the JSON paths the provisioner parses.

## Session entry schema

```nix
{ name = "Human Label"; dir = "projects/<slug>"; harness = "pi"; repo = "git@github.com:tigorlazuardi/<slug>.git"; enable = true; }
```

| field | required | meaning |
|---|---|---|
| `name` | yes | workspace label (human, spaces OK). Also slugged → server-unique agent name. |
| `dir` | yes | project dir **relative to `$HOME`** (e.g. `projects/foo`, or `homelab`). |
| `harness` | no | `"claude"` (default) or `"pi"`. claude gets native resume-on-restore; pi relies on `pi --continue` + the crash-restart loop. |
| `repo` | no | git SSH URL. If set AND `dir/.git` absent on provision, the provisioner `git clone`s it. Omit for local-only repos. |
| `enable` | no | defaults `true`. `false` = skip provisioning (see disable note). |

## Procedure — add a session

1. **Decide** harness (claude default; pi for the pi coding-agent), the dir slug
   (kebab-case of the name), and whether it needs a GitHub remote. Ask the user
   if unclear — these change the outcome.

2. **Create the project dir + git** (provisioner does NOT init git, only clones a
   remote). Guard the README so re-runs don't clobber:

   ```bash
   set -e
   mkdir -p ~/projects/<slug>
   cd ~/projects/<slug>
   [ -e README.md ] || printf '# <Name>\n' > README.md
   git init -q && git add -A && git commit -q -m "chore: init repo"
   git branch -M main
   ```

3. **GitHub repo — only if the user wants a remote.** Public vs private is the
   user's call; confirm. Uses `gh` (authed as `tigorlazuardi`):

   ```bash
   cd ~/projects/<slug>
   gh repo create <slug> --public --source=. --remote=origin \
     --description "<desc>" --push
   ```

   Local-only ("tidak perlu remote") → skip this; omit the `repo` field.

4. **Add the entry** to the `sessions` list in
   `modules/home/herdr-sessions.nix`. Mirror the pi-with-remote / pi-local /
   claude examples already in the list.

5. **Rebuild** to provision (needs the user — sudo password is interactive):

   ```
   ! sudo nixos-rebuild switch --flake ~/homelab#homeserver
   ```

   Never the bare `.#homeserver` (see `nixos-rebuild-flake-ref`).

## Disable / comment a session

Set `enable = false;` on the entry (keeps it in the list, documents intent).

**`enable = false` does NOT close a live workspace** — the provisioner only skips
*creating* it; an already-running pane keeps its RAM until closed by hand:

```bash
herdr workspace list
herdr workspace close <workspace-id>
```

## Gotchas

- **Agent names are server-unique** in herdr. The provisioner already slugs the
  label into the agent name — don't hand two sessions the same `name`.
- **Provisioner is idempotent**: existing workspace label present → skipped, left
  untouched (herdr's own snapshot restore owns it). Editing an entry's `dir`/
  `harness` after it was provisioned won't move a live workspace — close it and
  let the next rebuild recreate it.
- **CPU tier**: these sessions land in `sessions.slice` (coding tier) via the
  same module — no extra work.
