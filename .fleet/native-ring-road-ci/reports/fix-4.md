# Fix 4 — order Podman bootstrap after Home Manager activation

Verdict: PASS

## Change

Added `home-manager-ring-road-ci.service` to `After=` and `Requires=` for `ring-road-ci-podman-socket.service` in `services/ring-road-ci.nix`.

This closes the reviewed startup race: CI-user Home Manager activation must finish successfully before bootstrap starts `podman.socket`, so its Podman daemon sandbox drop-in is installed and the user manager reloaded first.

## Validation

- `git diff --check -- services/ring-road-ci.nix`: passed.
- `nix-instantiate --parse services/ring-road-ci.nix`: passed.
- Evaluated bootstrap `after` and `requires`: both contain `home-manager-ring-road-ci.service` and `user@1500.service`.
- `nix build --no-link --print-out-paths .#nixosConfigurations.homeserver.config.system.build.toplevel`: passed.
- Generated bootstrap unit contains matching `After=` and `Requires=` directives.
- Generated `home-manager-ring\x2droad\x2dci.service` exists in built closure.
- Exact immutable `nixos-rebuild build --flake .#homeserver` not run; orchestrator owns acceptance command.
- No switch, sudo, secret access/decryption, or live service operation performed.

## Residual risk

Live cutover must inspect effective Podman sandbox, restart any pre-existing daemon, and run negative bind-mount tests before runner starts. Unrelated pre-existing worktree changes remain untouched.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Committed source change is limited to services/ring-road-ci.nix, adding Home Manager activation ordering and requirement to Podman socket bootstrap exactly as requested by spec review."
    },
    {
      "id": "criterion-2",
      "status": "satisfied",
      "evidence": "Parse, evaluated dependency lists, full NixOS toplevel build, generated-unit assertions, commit inspection, and repository staging evidence are recorded."
    }
  ],
  "changedFiles": [
    "services/ring-road-ci.nix",
    ".fleet/native-ring-road-ci/reports/fix-4.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "git diff --check -- services/ring-road-ci.nix",
      "result": "passed",
      "summary": "No whitespace errors in focused source diff."
    },
    {
      "command": "nix-instantiate --parse services/ring-road-ci.nix",
      "result": "passed",
      "summary": "Nix source parsed successfully."
    },
    {
      "command": "nix eval --json .#nixosConfigurations.homeserver.config.systemd.services.ring-road-ci-podman-socket.after && nix eval --json .#nixosConfigurations.homeserver.config.systemd.services.ring-road-ci-podman-socket.requires",
      "result": "passed",
      "summary": "Both lists evaluate to home-manager-ring-road-ci.service and user@1500.service."
    },
    {
      "command": "nix eval --raw .#nixosConfigurations.homeserver.config.systemd.services.home-manager-ring-road-ci.serviceConfig.Type",
      "result": "failed",
      "summary": "Attribute path unavailable because hyphenated dynamic service key was parsed as path segments; generated closure inspection supplied required unit evidence instead."
    },
    {
      "command": "nix build --no-link --print-out-paths .#nixosConfigurations.homeserver.config.system.build.toplevel",
      "result": "passed",
      "summary": "Built /nix/store/1rldjv4qg50dk5574cwiadm6j48zk02x-nixos-system-homeserver-26.11.20260711.e7a3ca8."
    },
    {
      "command": "inspect generated ring-road-ci-podman-socket.service and home-manager-ring\\x2droad\\x2dci.service",
      "result": "passed",
      "summary": "Bootstrap has required ordering/requirement; Home Manager dependency unit exists."
    },
    {
      "command": "nixos-rebuild build --flake .#homeserver",
      "result": "not-run",
      "summary": "Exact immutable acceptance command reserved for orchestrator."
    },
    {
      "command": "git commit -m 'fix(ci): order podman after home activation'",
      "result": "passed",
      "summary": "Created focused conventional commit; only source change is services/ring-road-ci.nix, alongside this required report."
    }
  ],
  "validationOutput": [
    "Evaluated after: [home-manager-ring-road-ci.service, user@1500.service]",
    "Evaluated requires: [home-manager-ring-road-ci.service, user@1500.service]",
    "Generated After=home-manager-ring-road-ci.service user@1500.service",
    "Generated Requires=home-manager-ring-road-ci.service user@1500.service",
    "Generated home-manager-ring\\x2droad\\x2dci.service symlink exists",
    "NixOS system toplevel build completed successfully"
  ],
  "residualRisks": [
    "Live cutover/runtime isolation checks remain human-gated after switch.",
    "Any pre-existing CI-user Podman daemon must be restarted after activation before runner starts.",
    "Unrelated pre-existing worktree changes remain present but unstaged."
  ],
  "noStagedFiles": true,
  "diffSummary": "Added Home Manager activation as required ordered dependency of CI Podman socket bootstrap; no broader source changes.",
  "reviewFindings": [
    "resolved blocker: services/ring-road-ci.nix - Podman bootstrap now waits for and requires CI-user Home Manager activation."
  ],
  "manualNotes": "No tests added: focused Nix evaluation, full toplevel build, and generated-unit inspection cover this declarative dependency fix."
}
```
