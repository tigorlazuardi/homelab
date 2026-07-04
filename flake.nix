{
  description = "homelab — single-host NixOS homeserver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    # Agent/dev CLIs for the interactive homeserver user (claude-code, pi).
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Terminal workspace manager for the claude sessions (modules/home/herdr-sessions.nix).
    # Pinned to a release tag — pre-1.0, update deliberately (read the changelog).
    # No nixpkgs.follows: upstream builds against its own toolchain pins (rust+zig).
    herdr.url = "github:ogulcancelik/herdr/v0.7.1";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      quadlet-nix,
      ...
    }@inputs:
    {
      nixosConfigurations.homeserver = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          # disko + sops modules are imported by hardware/disko.nix and modules/sops.nix.
          home-manager.nixosModules.home-manager
          quadlet-nix.nixosModules.quadlet
          ./configuration.nix
        ];
      };
    };
}
