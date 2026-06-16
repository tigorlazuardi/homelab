{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "packfiles" # sh
      ''
        set -e
        export NIXPKGS_ALLOW_UNFREE=1
        build_path=$(nix build "nixpkgs#$1" --impure --no-link --print-out-paths)
        shift 1
        ${fd}/bin/fd --type f "$@" . $build_path
      ''
    )
    # packopen opens the build path of a package in a file manager if it's directory, an image viewer if it's an image, or a text editor if it's a text file.
    (writeShellScriptBin "packopen" # sh
      ''
        set -e
        export NIXPKGS_ALLOW_UNFREE=1
        build_path=$(nix build "nixpkgs#$1" --impure --no-link --print-out-paths)
        systemd-run --user ${xdg-utils}/bin/xdg-open $build_path
      ''
    )
    (writeShellScriptBin "build" # sh
      ''
        export NIXPKGS_ALLOW_UNFREE=1
        nix build --impure --expr "with import <nixpkgs> {}; callPackage $1 {}"
      ''
    )
    (writeShellScriptBin "json2nix" # sh
      ''
        set -e
        if [ -t 0 ]; then
          # No stdin input, use file argument
          nix eval --impure --expr "builtins.fromJSON (builtins.readFile \"$1\")"
        else
          # Read from stdin
          IFS= read text
          nix eval --impure --expr "builtins.fromJSON '''$text'''"
        fi
      ''
    )
  ];
}
