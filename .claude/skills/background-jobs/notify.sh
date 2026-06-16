#!/usr/bin/env bash
# claude_notify <message> — send one Telegram message via the homelab bot.
# Reuses the bot smartd + Grafana alerts already use. Source this file inside a
# background job's command, then call claude_notify on exit. See SKILL.md.
#
#   source ~/homelab/.claude/skills/background-jobs/notify.sh
#   claude_notify "✅ job done"
#
# Creds: post-switch from sops-nix srv-owned plaintext under /run/secrets;
# pre-switch/ad-hoc by decrypting secrets/smartd.yaml (needs /opt/age-key.txt).

claude_notify() {
  local tok chat
  if [ -r /run/secrets/observability/telegram_bot_token ]; then
    tok=$(cat /run/secrets/observability/telegram_bot_token)
    chat=$(cat /run/secrets/observability/telegram_chat_id)
  else
    local y
    y=$(sops -d "$HOME/homelab/secrets/smartd.yaml") || {
      echo "claude_notify: cannot read telegram creds" >&2
      return 1
    }
    tok=$(printf '%s\n' "$y" | sed -n 's/^telegram_bot_token: *//p' | tr -d '"')
    chat=$(printf '%s\n' "$y" | sed -n 's/^telegram_chat_id: *//p' | tr -d '"')
  fi
  curl -s "https://api.telegram.org/bot${tok}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${1:-(no message)}" >/dev/null
}
