# Native Ring Road CI standards isolation fix

Verdict: PASS

Report ref: `.fleet/native-ring-road-ci/reports/fix-2.md`

## Change

Addressed all mandatory standards-review findings within approved native-runner scope:

- Podman API daemon now receives a CI-user-only systemd drop-in denying production paths. This applies the mount namespace to daemon and descendants that service workflow API requests, rather than only to runner process.
- Denied path set covers `/home/srv`, `/run/user/1001`, `/srv/data`, `/var/lib/containers`, and every documented production storage tier under `/var/mnt/{fenrir,nas,state,wolf}`.
- Runner remains in dedicated `user-1500.slice`; Podman daemon and rootless container descendants execute below same dedicated user manager/slice. Existing slice budget remains `CPUQuota=400%`, `CPUWeight=10`, `MemoryHigh=8G`.
- Service inventory no longer claims nspawn isolation. It states native dedicated-user trust ceiling, daemon path denial, dedicated user-slice budget, and VM upgrade path for untrusted workflows.

`systemd.user.services.podman` was deliberately not used for sandbox declaration: NixOS system user units are global to every user manager and would also hide production paths from `srv`'s production Podman. Home Manager drop-in scopes override to `ring-road-ci` user only.

## Validation

- `nix-instantiate --parse services/ring-road-ci.nix`: PASS.
- Focused isolation self-check: PASS. Evaluated CI-user Podman drop-in includes every denied production path; runner slice equals `user-1500.slice`; slice retains 400%/10/8G; vendor Podman service retains `Delegate=true`; stale nspawn claims/wiring are absent.
- `nix build --no-link .#nixosConfigurations.homeserver.config.system.build.toplevel`: PASS; built `/nix/store/f36b90k7vn73li0xv6iaycz5s013a69q-nixos-system-homeserver-26.11.20260711.e7a3ca8`.
- Generated runner unit inspection: `Slice=user-1500.slice` plus production `InaccessiblePaths` present.
- Generated CI Home Manager drop-in evaluation: daemon `InaccessiblePaths` contains all production roots. Build confirms drop-in generation; it is user-scoped at activation.
- `git diff --check -- services/ring-road-ci.nix services/default.nix`: PASS.
- Exact `nixos-rebuild build --flake .#homeserver`: not run; orchestrator-owned.

## Residual risk

No live switch per contract. Human cutover must inspect effective CI user `podman.service`, daemon/container cgroup paths, and negatively test API bind mounts against all denied paths. Native sandbox is suitable only for private trusted repo/internal reviewed PRs; VM remains required for fork/external/untrusted workflow execution.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "services/ring-road-ci.nix adds CI-user-scoped Podman daemon production-path denial and preserves shared dedicated user-slice controls; services/default.nix only corrects stale nspawn security documentation."
    }
  ],
  "changedFiles": [
    "services/ring-road-ci.nix",
    "services/default.nix",
    ".fleet/native-ring-road-ci/reports/fix-2.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "nix-instantiate --parse services/ring-road-ci.nix",
      "result": "passed",
      "summary": "Nix source parsed successfully."
    },
    {
      "command": "focused isolation self-check using nix eval, grep, jq, and rg",
      "result": "passed",
      "summary": "Asserted daemon denied paths, runner/user slice resource controls, Podman delegation, and absence of stale nspawn wiring/claims."
    },
    {
      "command": "nix build --no-link .#nixosConfigurations.homeserver.config.system.build.toplevel",
      "result": "passed",
      "summary": "Built NixOS system derivation /nix/store/f36b90k7vn73li0xv6iaycz5s013a69q-nixos-system-homeserver-26.11.20260711.e7a3ca8."
    },
    {
      "command": "inspect generated runner unit, user slice, Podman vendor unit, and evaluated CI-user daemon drop-in",
      "result": "passed",
      "summary": "Confirmed runner Slice=user-1500.slice, 400%/10/8G controls, vendor Delegate=true, and CI-scoped daemon InaccessiblePaths."
    },
    {
      "command": "git diff --check -- services/ring-road-ci.nix services/default.nix",
      "result": "passed",
      "summary": "No whitespace errors in focused source diff."
    }
  ],
  "validationOutput": [
    "focused isolation self-check: PASS",
    "Nix system derivation build: PASS",
    "daemon denied paths: /home/srv, /run/user/1001, /srv/data, /var/lib/containers, /var/mnt/fenrir, /var/mnt/nas, /var/mnt/state, /var/mnt/wolf",
    "shared CI boundary: runner user-1500.slice; dedicated user manager and daemon/container descendants under user-1500.slice; CPUQuota=400%, CPUWeight=10, MemoryHigh=8G",
    "exact orchestrator check not run"
  ],
  "residualRisks": [
    "No live switch: effective daemon mount denial, negative API bind-mount tests, and runner/daemon/test-container cgroup paths remain mandatory human cutover validation.",
    "Native runner trust ceiling remains private trusted repo/internal reviewed PRs; use VM for untrusted workflows."
  ],
  "noStagedFiles": true,
  "diffSummary": "Hardened workflow-controlled Podman daemon against production-path bind mounts, retained shared dedicated user-slice budget, and corrected stale nspawn inventory documentation.",
  "reviewFindings": [
    "resolved blocker: Podman daemon receives CI-user-scoped production InaccessiblePaths.",
    "resolved high: runner, dedicated user manager, daemon, and delegated container descendants share user-1500.slice budget.",
    "resolved medium: service inventory now documents native boundary and untrusted-workflow VM ceiling."
  ],
  "manualNotes": "No switch, sudo, secret access, push, destructive operation, Ring Road repo edit, or exact orchestrator check. Unrelated dirty changes preserved."
}
```
