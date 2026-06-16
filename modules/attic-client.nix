{ pkgs, lib, config, ... }:
let
  cfg = config.services.attic-client;
in
{
  options.services.attic-client = {
    enable = lib.mkEnableOption "Attic binary cache client";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.tigor.web.id";
      description = "URL of the Attic server";
    };

    cacheName = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Name of the cache to use";
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      description = "Public key for the cache (get from: attic cache info <cache-name>)";
      example = "main:abc123...";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.attic-client ];

    nix.settings = {
      substituters = [ "${cfg.serverUrl}/${cfg.cacheName}" ];
      trusted-public-keys = [ cfg.publicKey ];
    };
  };
}
