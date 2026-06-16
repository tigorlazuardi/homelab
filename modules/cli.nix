{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Modern CLI tools
    bat # cat replacement with syntax highlighting
    eza # ls replacement
    yazi # terminal file manager
    fd # find replacement
    ripgrep # grep replacement
    fzf # fuzzy finder
    zoxide # cd replacement with frecency
    btop # top/htop replacement
    duf # df replacement
    dust # du replacement
    delta # git diff viewer
    jq # JSON processor
    tldr # simplified man pages

    infisical
    just
  ];
}
