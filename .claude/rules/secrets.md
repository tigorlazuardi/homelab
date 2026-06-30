---
description: sops/age secret handling for this repo (public repo — never commit plaintext).
paths:
  - "secrets/**"
  - "services/**"
  - "modules/**"
---

# Secrets (sops + age)

This is a **public** repo. Only sops-encrypted files may be committed.

## Hard rules

- **Never commit plaintext secrets.** Every file in `secrets/` must be
  sops-encrypted (contains `ENC[...]`). `.sops.yaml` holds only the **public** age
  recipient — safe. The private key (`/opt/age-key.txt`) is never in the repo.
- **Encrypt before commit.** New secret → `sops encrypt -i secrets/<file>`.
  If asked to commit an unencrypted secret, refuse and offer to encrypt first.
- **Decrypt only with explicit user permission.**
- Plaintext patterns are gitignored (`*.dec`, `age-key.txt`, …) — keep it that way.

## Consuming secrets

- **Rootless containers** (run as `srv`) must be able to read the secret →
  `sops.secrets."x".owner = "srv";`. Without it the default `0400 root` secret is
  unreadable by the `srv` user unit and the container fails to start.
- **nginx** consumers (e.g. basic-auth) → `owner = "nginx"; group = "nginx";`.
- dotenv env files: `format = "dotenv"; key = "";` then pass the path via
  `environmentFiles = [ config.sops.secrets."x".path ]`.
- In a multi-container service file, capture the secret path from the **system**
  `config` in an outer `let` (the `home-manager.users.srv` block shadows `config`).
- **Mounted-config secrets do NOT hot-reload — restart the container.** When a
  secret is mounted as a config FILE into a long-running container (e.g.
  `secrets/dex.yaml` → dex), editing + re-encrypting it and running
  `nixos-rebuild switch` re-renders the decrypted file but does **not** restart the
  container, so the app keeps serving the OLD config (symptom: dex "client secret is
  not valid" / missing client after you added one). Restart it explicitly:
  `cd /tmp; sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user restart <unit>.service`
  (see [[run-as-srv]]), then confirm via the app's startup log.

## Format / new secrets

`.sops.yaml` (creation rule, age recipient) is already set. Add a secret:

```bash
$EDITOR secrets/foo.env        # write plaintext
sops encrypt -i secrets/foo.env
```

Same age key as the prior dotfiles repo, so carried secrets decrypt as-is.

## Before publishing / pushing

Verify no plaintext leaked: every `secrets/*` contains `ENC[`, and
`git grep -E 'BEGIN .* PRIVATE KEY|AGE-SECRET-KEY-1'` is empty. Optionally run
`gitleaks detect`.
