{ inputs, lib, ... }:
{
  imports = [
    ./hardware

    # System (flat — one concern per file; files may co-locate system + home-manager)
    ./modules/boot.nix
    ./modules/networking.nix
    ./modules/nix.nix
    ./modules/sops.nix
    ./modules/locale.nix
    ./modules/nix-ld.nix
    ./modules/sudo.nix
    ./modules/ssh.nix
    ./modules/users.nix
    ./modules/podman.nix

    # Shell / tooling
    ./modules/cli.nix
    ./modules/fish.nix
    ./modules/direnv.nix
    ./modules/scripts.nix
    ./modules/git.nix
    ./modules/neovim.nix
    ./modules/attic-client.nix
    ./modules/dev.nix

    ./services
  ];

  time.timeZone = lib.mkDefault "Asia/Jakarta";

  # Home Manager scaffold — set once. Concern files add `home-manager.users.<u>.*`
  # slices that merge here (locality of behaviour).
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    backupFileExtension = "bak";
    sharedModules = [ inputs.quadlet-nix.homeManagerModules.quadlet ];
  };

  system.stateVersion = "25.11";
}
