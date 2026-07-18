# Handover 1 — Home Manager unit identity fix

Verdict: HANDOVER

## Change

- `services/ring-road-ci.nix`: accept NixOS module `utils`, derive `homeManagerService` with `utils.escapeSystemdPath user`, and use exact escaped service identity in bootstrap `after` and `requires`.
- Scope limited to standards-review-2 finding. No live switch, secret access, or immutable build check performed.

## Validation

- `nix-instantiate --parse services/ring-road-ci.nix` passed.
- Evaluated `ring-road-ci-podman-socket.after` and `.requires`; both contain `home-manager-ring\\x2droad\\x2dci.service`.
- `git diff --check -- services/ring-road-ci.nix` passed.
- Exact `nixos-rebuild build --flake .#homeserver` intentionally not run; reviewer/check phase owns it.

## Residual risk

- Full NixOS build and generated-unit inspection remain for independent check/review.
- Existing unrelated worktree changes remain untouched.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "services/ring-road-ci.nix now derives Home Manager unit identity with utils.escapeSystemdPath and uses it in both after and requires."
    },
    {
      "id": "criterion-2",
      "status": "satisfied",
      "evidence": "Focused parse, evaluated-option assertions, diff check, commit, and residual risks are recorded for independent review."
    }
  ],
  "changedFiles": [
    "services/ring-road-ci.nix",
    ".fleet/native-ring-road-ci-followup/reports/handover-1.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "nix-instantiate --parse services/ring-road-ci.nix",
      "result": "passed",
      "summary": "Nix parser accepted module."
    },
    {
      "command": "nix eval --json '.#nixosConfigurations.homeserver.config.systemd.services.ring-road-ci-podman-socket.after' | jq -e 'index(escaped-unit) != null'",
      "result": "passed",
      "summary": "After list contains home-manager-ring\\x2droad\\x2dci.service."
    },
    {
      "command": "nix eval --json '.#nixosConfigurations.homeserver.config.systemd.services.ring-road-ci-podman-socket.requires' | jq -e 'index(escaped-unit) != null'",
      "result": "passed",
      "summary": "Requires list contains home-manager-ring\\x2droad\\x2dci.service."
    },
    {
      "command": "git diff --check -- services/ring-road-ci.nix",
      "result": "passed",
      "summary": "No whitespace errors."
    },
    {
      "command": "nixos-rebuild build --flake .#homeserver",
      "result": "not-run",
      "summary": "Immutable check reserved for reviewer/check phase."
    }
  ],
  "validationOutput": [
    "Evaluated after: [home-manager-ring\\x2droad\\x2dci.service, user@1500.service].",
    "Evaluated requires contains same escaped Home Manager service identity.",
    "Nix parse passed."
  ],
  "residualRisks": [
    "Full NixOS build and generated-unit inspection remain for reviewer/check phase.",
    "Live runtime behavior remains untested."
  ],
  "noStagedFiles": true,
  "diffSummary": "Replace literal unescaped Home Manager dependency with unit name derived through nixpkgs systemd path escaping.",
  "reviewFindings": [
    "no blockers in focused validation"
  ],
  "manualNotes": "Existing unrelated dirty worktree files were not staged or modified by this handover."
}
```
