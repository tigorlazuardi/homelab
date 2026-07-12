# Headless dev shell for the human user (ex claude-code environment, decrufted:
# desktop screenshot tooling + planet-melon-coupled secrets dropped).
{ pkgs, ... }:
{
  home-manager.users.homeserver.home.packages = with pkgs; [
    ripgrep
    fd
    gh
    jq
    curl
    wget
    tree
    nodejs
    python3
    gnumake
    gcc
    nixfmt
    chezmoi
    oscclip # osc52-copy/osc52-paste — clipboard over terminal escape (SSH-safe)
    uv # python pkg/proj manager; also provides uvx (run tools, e.g. mcp servers)
    ttyd # share a terminal over http (e.g. herdr/tui in browser)
  ];
}
