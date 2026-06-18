# Agent / dev CLI tooling for the interactive `homeserver` user. Headless port of
# the old deploy's pi-coding-agent + claude-code home-manager modules. Skips the
# desktop-only bits (playwright browsers, spectacle screenshot, opencode-desktop)
# and the old .pi dotfiles symlink + secrets.fish (paths/secret not carried).
{
  pkgs,
  inputs,
  config,
  osConfig,
  ...
}:
{
  home.packages =
    (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      claude-code
      pi
    ])
    ++ (with pkgs; [
      # session / runtimes
      zellij # keep session alive
      nodejs
      pnpm
      bun
      ffmpeg
      # dev tools (those not already in the system cli.nix)
      gh # GitHub CLI
      tree
      gnumake
      gcc
      cmake
      nixfmt
      chezmoi
      python3
      wget
    ]);

  programs.npm = {
    enable = true;
    settings.prefix = "${config.home.homeDirectory}/.local/npm";
  };

  # User shell extras (system fish.nix already provides the base + aliases).
  programs.fish = {
    enable = true;
    inherit (osConfig.programs.fish) package;
    shellAliases.clauded = "claude --permission-mode=bypassPermissions";
    interactiveShellInit = ''
      fish_add_path ${config.programs.npm.settings.prefix}/bin
      fish_add_path ${config.home.homeDirectory}/.bun/bin
      fish_add_path ${config.home.homeDirectory}/go/bin
    '';
  };

  # Strip Claude's self-promo trailers from commit messages (user preference).
  programs.git.hooks.commit-msg = pkgs.writeShellScript "clean-claude-self-promote" ''
    COMMIT_MSG_FILE=$1
    TMP="''${COMMIT_MSG_FILE}.processed.$$"
    ${pkgs.gnugrep}/bin/grep -vF "🤖 Generated with" "$COMMIT_MSG_FILE" \
      | ${pkgs.gnugrep}/bin/grep -vF "Co-Authored-By" > "$TMP"
    ${pkgs.gawk}/bin/awk '
      BEGIN { started=0; pend=0 }
      NF { if(!started){started=1} else if(pend){print ""}; print $0; pend=0; next }
      !NF { if(started){pend=1} }
    ' "$TMP" > "$COMMIT_MSG_FILE"
    rm -f "$TMP"
    exit 0
  '';
}
