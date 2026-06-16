# smartd - S.M.A.R.T. disk monitoring with Telegram notifications
# Uses smartd's built-in diminishing mode: 1, 2, 4, 8, 16, 32... days
{ config, pkgs, ... }:
let
  shortScriptPath = "/run/smartd-notify";

  # Notification script for Telegram
  notifyScript = pkgs.writeShellScript "smartd-notify" ''
        set -euo pipefail

        # Load secrets from sops paths
        TELEGRAM_BOT_TOKEN=$(${pkgs.coreutils}/bin/cat ${
          config.sops.secrets."smartd/telegram_bot_token".path
        })
        TELEGRAM_CHAT_ID=$(${pkgs.coreutils}/bin/cat ${
          config.sops.secrets."smartd/telegram_chat_id".path
        })

        # smartd provides these environment variables
        DEVICE="''${SMARTD_DEVICE:-unknown}"
        MESSAGE="''${SMARTD_MESSAGE:-No message}"
        FAILTYPE="''${SMARTD_FAILTYPE:-Unknown}"

        HOSTNAME=$(${pkgs.nettools}/bin/hostname)
        TIMESTAMP=$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')

        # Get disk details via smartctl
        DISK_INFO=$(${pkgs.smartmontools}/bin/smartctl -i "$DEVICE" 2>/dev/null || true)
        VENDOR=$(echo "$DISK_INFO" | ${pkgs.gnugrep}/bin/grep -E "^(Model Family|Vendor):" | ${pkgs.coreutils}/bin/cut -d: -f2 | ${pkgs.findutils}/bin/xargs || echo "N/A")
        MODEL=$(echo "$DISK_INFO" | ${pkgs.gnugrep}/bin/grep -E "^(Device Model|Model Number|Product):" | ${pkgs.coreutils}/bin/cut -d: -f2 | ${pkgs.findutils}/bin/xargs || echo "N/A")
        SERIAL=$(echo "$DISK_INFO" | ${pkgs.gnugrep}/bin/grep -E "^Serial Number:" | ${pkgs.coreutils}/bin/cut -d: -f2 | ${pkgs.findutils}/bin/xargs || echo "N/A")
        CAPACITY=$(echo "$DISK_INFO" | ${pkgs.gnugrep}/bin/grep -E "^(User Capacity|Total NVM Capacity):" | ${pkgs.coreutils}/bin/cut -d: -f2 | ${pkgs.findutils}/bin/xargs || echo "N/A")

        MSG="<b>SMART Alert</b>

    <b>Host:</b> $HOSTNAME
    <b>Device:</b> $DEVICE
    <b>Brand:</b> $VENDOR
    <b>Model:</b> $MODEL
    <b>Serial:</b> $SERIAL
    <b>Capacity:</b> $CAPACITY
    <b>Type:</b> $FAILTYPE
    <b>Time:</b> $TIMESTAMP

    <b>Message:</b>
    <code>$MESSAGE</code>"

        ${pkgs.curl}/bin/curl -s -X POST \
          "https://api.telegram.org/bot''${TELEGRAM_BOT_TOKEN}/sendMessage" \
          -d chat_id="''${TELEGRAM_CHAT_ID}" \
          -d parse_mode="HTML" \
          -d text="$MSG" \
          >/dev/null 2>&1 || true
  '';
in
{
  # Sops secrets for Telegram credentials
  sops.secrets."smartd/telegram_bot_token" = {
    sopsFile = ../secrets/smartd.yaml;
    key = "telegram_bot_token";
    mode = "0400";
    owner = "root";
    group = "root";
  };
  sops.secrets."smartd/telegram_chat_id" = {
    sopsFile = ../secrets/smartd.yaml;
    key = "telegram_chat_id";
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # Create short symlink to avoid MAXLINELEN limit in smartd.conf
  systemd.tmpfiles.rules = [
    "L+ ${shortScriptPath} - - - - ${notifyScript}"
  ];

  # Enable smartd service
  services.smartd = {
    enable = true;
    autodetect = true;

    # Use short symlink path to keep line under 256 chars
    # -s: short test daily 2am, long test Saturday 3am
    defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,50 -m <nomail> -M exec ${shortScriptPath} -M diminishing";
  };
}
