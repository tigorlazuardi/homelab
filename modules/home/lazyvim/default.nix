{ config, pkgs, ... }:
{
  imports = [ ./go.nix ];

  # neovim binary comes from the system module (modules/neovim.nix). Enabling
  # programs.neovim here generates its own .config/nvim/init.lua, which collides
  # with the whole-dir symlink below ("Error installing file ... outside $HOME").
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/homelab/modules/home/lazyvim/nvim";
  home.packages = with pkgs; [
    cargo
    lsof
    statix
    typescript-go
    biome
    unzip
    go
  ];
}
