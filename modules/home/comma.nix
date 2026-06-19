# comma — run a program from nixpkgs without installing it: `, cowsay`.
# nix-index-database ships a prebuilt weekly index, so the locate DB that
# comma needs is provided declaratively (no manual `nix-index` run).
{ inputs, ... }:
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];
  # Replaces the command-not-found handler + installs the nix-index DB.
  programs.nix-index.enable = true;
  # Installs the `comma` binary wired to that DB.
  programs.nix-index-database.comma.enable = true;
}
