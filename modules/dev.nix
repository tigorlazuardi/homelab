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
    gopls # Go language server (nixpkgs)
    nixfmt
    chezmoi
    oscclip # osc52-copy/osc52-paste — clipboard over terminal escape (SSH-safe)
    uv # python pkg/proj manager; also provides uvx (run tools, e.g. mcp servers)
    ttyd # share a terminal over http (e.g. herdr/tui in browser)

    # python dev
    ruff
    mypy
    pyright
    pipx

    # language servers
    nixd
    lua-language-server
    typescript-language-server
    vscode-langservers-extracted
    yaml-language-server
    bash-language-server
    marksman

    # formatters/linters
    shfmt
    shellcheck
    stylua
    prettier
    taplo
    yamllint
    hadolint

    # go toolchain
    go
    delve
    golangci-lint
    gotools

    # office/data-stack CLIs
    kcat
    postgresql
    redis
    grpcurl
    kubectl
    k9s
    httpie
    yq-go
    websocat

    # misc CLIs + git
    lazygit
    git-lfs
    watchexec
    hyperfine
    jless
    sd
    ncdu
    unzip
  ];
}
