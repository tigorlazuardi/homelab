# Fix 1 — escaped Home Manager dependency identity

Verdict: PASS
Route: frontier

## Change

- `services/ring-road-ci.nix`: accept NixOS module `utils`, derive `homeManagerService` with `utils.escapeSystemdPath user`, and reuse exact escaped unit identity in both `after` and `requires`.
- Scope stayed limited to reviewer finding. No contract, route, check command, state, secret, or runtime operation changed.

## Evidence

### Changed files

- `services/ring-road-ci.nix`
- `.fleet/native-ring-road-ci-followup/reports/fix-1.md`

### Tests added or updated

- None. Focused Nix evaluation directly checks generated dependency identity; no new test framework or abstraction needed.

### Commands run

1. `nixfmt --check services/ring-road-ci.nix` — passed.
2. `git diff --check` — passed with no output.
3. Focused `nix eval` + `jq` assertion over `systemd.services.ring-road-ci-podman-socket.after`, `.requires`, and generated Home Manager service attr names — passed.
4. `nix eval --raw '.#nixosConfigurations.homeserver.config.system.build.toplevel.drvPath'` — passed; evaluated `/nix/store/sblnqy3cw8dvnwmawd65lhdsn38ph9vv-nixos-system-homeserver-26.11.20260711.e7a3ca8.drv`.
5. Exact acceptance command `nixos-rebuild build --flake .#homeserver` — not run; orchestrator owns exact contract check.

### Validation output

- `After=["home-manager-ring\\x2droad\\x2dci.service","user@1500.service"]`
- `Requires=["home-manager-ring\\x2droad\\x2dci.service","user@1500.service"]`
- Generated Home Manager units include `home-manager-ring\\x2droad\\x2dci`.
- Focused assertion also confirms literal `home-manager-ring-road-ci.service` is absent from both dependency lists.
- NixOS toplevel evaluates successfully after change.

## Residual risks

- Exact full build remains pending orchestrator acceptance check.
- Live systemd startup ordering remains pending human-approved switch/live acceptance.
- Existing unrelated unstaged/untracked worktree changes remain untouched and excluded from this commit.

## Review findings

- Reviewer high finding resolved: dependency now uses same `utils.escapeSystemdPath` helper Home Manager uses to generate service name.
- No new blockers found in focused validation.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "services/ring-road-ci.nix derives one escaped Home Manager service identity with utils.escapeSystemdPath and reuses it in after/requires; only source file and required report are included."
    },
    {
      "id": "criterion-2",
      "status": "satisfied",
      "evidence": "Focused Nix evaluation proves After and Requires exactly match generated home-manager-ring\\\\x2droad\\\\x2dci.service and reject literal unescaped identity."
    }
  ],
  "changedFiles": [
    "services/ring-road-ci.nix",
    ".fleet/native-ring-road-ci-followup/reports/fix-1.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "nixfmt --check services/ring-road-ci.nix",
      "result": "passed",
      "summary": "Nix formatting check passed."
    },
    {
      "command": "git diff --check",
      "result": "passed",
      "summary": "No whitespace errors."
    },
    {
      "command": "focused nix eval + jq assertion for escaped Home Manager dependency identity",
      "result": "passed",
      "summary": "After/Requires match generated escaped unit; literal unescaped dependency absent."
    },
    {
      "command": "nix eval --raw '.#nixosConfigurations.homeserver.config.system.build.toplevel.drvPath'",
      "result": "passed",
      "summary": "NixOS toplevel evaluated to /nix/store/sblnqy3cw8dvnwmawd65lhdsn38ph9vv-nixos-system-homeserver-26.11.20260711.e7a3ca8.drv."
    },
    {
      "command": "nixos-rebuild build --flake .#homeserver",
      "result": "not-run",
      "summary": "Exact acceptance check reserved for orchestrator."
    }
  ],
  "validationOutput": [
    "After and Requires each contain home-manager-ring\\\\x2droad\\\\x2dci.service.",
    "Generated service attrs include home-manager-ring\\\\x2droad\\\\x2dci.",
    "Literal home-manager-ring-road-ci.service is absent from both dependency lists.",
    "NixOS toplevel evaluation passed."
  ],
  "residualRisks": [
    "Exact full build pending orchestrator acceptance check.",
    "Live startup behavior pending human-approved switch/live acceptance.",
    "Unrelated pre-existing worktree changes remain untouched."
  ],
  "noStagedFiles": true,
  "diffSummary": "Use NixOS systemd escaping helper once, then reference exact escaped Home Manager unit in both bootstrap dependency lists.",
  "reviewFindings": [
    "no blockers: focused validation resolves standards reviewer high finding."
  ],
  "manualNotes": "No live switch, secret access, contract/state edit, or exact acceptance build performed."
}
```
