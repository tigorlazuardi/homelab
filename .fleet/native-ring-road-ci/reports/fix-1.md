# Native Ring Road CI bootstrap dependency fix

Verdict: PASS

Report ref: `.fleet/native-ring-road-ci/reports/fix-1.md`

## Change

Removed `home-manager-ring-road-ci.service` from `ring-road-ci-podman-socket` ordering and required dependencies. NixOS Home Manager integration does not generate that per-user system unit; requiring it prevented Podman bootstrap and therefore runner activation after switch. Bootstrap now depends only on generated `user@1500.service`; generated Home Manager user configuration remains activated through normal NixOS Home Manager activation.

Scope stayed within `services/ring-road-ci.nix` plus this required report. No switch, sudo, secret access, exact orchestrator check, or unrelated-file edit occurred.

## Validation

- `nix-instantiate --parse services/ring-road-ci.nix`: PASS.
- Focused `nix eval` of bootstrap `requires`: `["user@1500.service"]`.
- Focused `nix eval` of bootstrap `after`: `["user@1500.service"]`.
- Repository search for `home-manager-ring-road-ci.service`: no matches.
- `git diff --check -- services/ring-road-ci.nix`: PASS.
- Exact `nixos-rebuild build --flake .#homeserver`: not run; orchestrator-owned.

## Residual risk

No live switch per contract. Human cutover must confirm Podman socket bootstrap and runner activation. Full flake build remains orchestrator gate.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "services/ring-road-ci.nix removes only nonexistent Home Manager system-unit dependency from Podman bootstrap; evaluated after/requires now contain only user@1500.service."
    }
  ],
  "changedFiles": [
    "services/ring-road-ci.nix",
    ".fleet/native-ring-road-ci/reports/fix-1.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "nix-instantiate --parse services/ring-road-ci.nix",
      "result": "passed",
      "summary": "Nix source parsed successfully."
    },
    {
      "command": "nix eval --json .#nixosConfigurations.homeserver.config.systemd.services.ring-road-ci-podman-socket.requires",
      "result": "passed",
      "summary": "Evaluated required units equal [\"user@1500.service\"]."
    },
    {
      "command": "nix eval --json .#nixosConfigurations.homeserver.config.systemd.services.ring-road-ci-podman-socket.after",
      "result": "passed",
      "summary": "Evaluated ordering units equal [\"user@1500.service\"]."
    },
    {
      "command": "repository search for home-manager-ring-road-ci.service",
      "result": "passed",
      "summary": "No references remain."
    },
    {
      "command": "git diff --check -- services/ring-road-ci.nix",
      "result": "passed",
      "summary": "No whitespace errors."
    }
  ],
  "validationOutput": [
    "parse: PASS",
    "bootstrap requires: [\"user@1500.service\"]",
    "bootstrap after: [\"user@1500.service\"]",
    "home-manager-ring-road-ci.service references: none",
    "exact orchestrator check not run"
  ],
  "residualRisks": [
    "No live switch: post-switch Podman socket bootstrap and runner activation remain human validation.",
    "Full nixos-rebuild build remains orchestrator-owned."
  ],
  "noStagedFiles": true,
  "diffSummary": "Removed nonexistent Home Manager system-unit dependency that blocked native Podman bootstrap and runner activation.",
  "reviewFindings": [
    "no blockers in focused dependency evaluation"
  ],
  "manualNotes": "Unrelated dirty changes preserved. No switch, sudo, secret access, source-scope widening, or exact orchestrator check."
}
```
