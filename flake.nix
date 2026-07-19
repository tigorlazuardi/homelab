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
    # Browser frontend for the herdr server (herdr.tigor.web.id). Standalone Go
    # binary with the frontend embedded; consumes OUR herdr binary via its HM
    # module (herdrPackage pinned to inputs.herdr, not the module's pkgs.herdr
    # fallback). Own nixpkgs pin like herdr — self-contained build, no follows.
    herdr-web-tui.url = "github:tigorlazuardi/herdr-web-tui";
    open-design = {
      url = "github:nexu-io/open-design";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    switchd.url = "github:tigorlazuardi/nixos-switch-approval-telegram-portal";
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
