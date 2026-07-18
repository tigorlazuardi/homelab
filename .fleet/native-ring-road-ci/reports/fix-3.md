# Fix 3 — remove invalid SOPS service dependency

Verdict: PASS

## Change

Removed only explicit `sops-install-secrets.service` entries from `github-runner-ring-road-ci.service` `after` and `requires` lists in `services/ring-road-ci.nix`.

Retained:

- `services.github-runners.ring-road-ci.tokenFile = config.sops.secrets."ring-road-ci/runner-pat".path`
- runner dependency on `ring-road-ci-podman-socket.service`
- all runner isolation, restart, resource, secret ownership, and telemetry settings

## Validation

- `git diff --check`: passed.
- `nix-instantiate --parse services/ring-road-ci.nix`: passed.
- `nix eval` confirms `config.sops.useSystemdActivation = false`.
- `nix eval` confirms evaluated runner `After=` contains network units plus `ring-road-ci-podman-socket.service`, and `Requires=` contains only `ring-road-ci-podman-socket.service`.
- `nix eval` confirms runner `tokenFile` remains `/run/secrets/ring-road-ci/runner-pat`.
- `nix build --no-link .#nixosConfigurations.homeserver.config.system.build.toplevel`: passed; five affected derivations built.
- Generated `github-runner-ring-road-ci.service` contains no `sops-install-secrets.service` dependency and retains `ring-road-ci-podman-socket.service` ordering/requirement.
- Immutable exact acceptance command `nixos-rebuild build --flake .#homeserver` not run here; orchestrator owns exact acceptance run.
- No switch, sudo, secret decryption, or live service operation performed.

## Residual risk

Exact orchestrator-owned acceptance command remains pending. Live activation/runtime validation remains human-gated after switch. Unrelated pre-existing worktree changes were not staged or modified by this fix.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "services/ring-road-ci.nix removes only nonexistent sops-install-secrets.service After/Requires entries while retaining tokenFile and Podman socket dependency semantics."
    },
    {
      "id": "criterion-2",
      "status": "satisfied",
      "evidence": "Focused parse, evaluation, full NixOS toplevel build, generated-unit inspection, diff check, and repository state evidence recorded here."
    }
  ],
  "changedFiles": [
    "services/ring-road-ci.nix",
    ".fleet/native-ring-road-ci/reports/fix-3.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "git diff --check",
      "result": "passed",
      "summary": "No whitespace errors."
    },
    {
      "command": "nix-instantiate --parse services/ring-road-ci.nix",
      "result": "passed",
      "summary": "Nix syntax parsed."
    },
    {
      "command": "nix eval --json .#nixosConfigurations.homeserver.config.sops.useSystemdActivation",
      "result": "passed",
      "summary": "Evaluated false."
    },
    {
      "command": "nix eval runner After/Requires/tokenFile options",
      "result": "passed",
      "summary": "Invalid SOPS unit absent; Podman socket dependency and /run/secrets tokenFile retained."
    },
    {
      "command": "nix build --no-link .#nixosConfigurations.homeserver.config.system.build.toplevel",
      "result": "passed",
      "summary": "Full NixOS toplevel built successfully; five affected derivations built."
    },
    {
      "command": "inspect generated github-runner-ring-road-ci.service",
      "result": "passed",
      "summary": "After/Requires omit sops-install-secrets.service and retain ring-road-ci-podman-socket.service."
    },
    {
      "command": "nixos-rebuild build --flake .#homeserver",
      "result": "not-run",
      "summary": "Immutable exact acceptance command reserved for orchestrator."
    }
  ],
  "validationOutput": [
    "Evaluated sops.useSystemdActivation: false",
    "Evaluated runner After: [network.target, network-online.target, ring-road-ci-podman-socket.service]",
    "Evaluated runner Requires: [ring-road-ci-podman-socket.service]",
    "Evaluated runner tokenFile: /run/secrets/ring-road-ci/runner-pat",
    "Generated unit invalid dependency absent: PASS",
    "NixOS system toplevel build completed successfully"
  ],
  "residualRisks": [
    "Exact orchestrator-owned nixos-rebuild acceptance command remains pending.",
    "Live service startup remains human-gated after switch."
  ],
  "noStagedFiles": true,
  "diffSummary": "Removed invalid explicit SOPS systemd ordering and requirement from native Ring Road CI runner; retained tokenFile and Podman socket runtime dependency semantics.",
  "reviewFindings": [
    "no blockers"
  ],
  "manualNotes": "No tests added: focused evaluated-config, generated-unit, and full NixOS build checks cover this declarative dependency-only fix. Unrelated pre-existing worktree changes remain untouched."
}
```
