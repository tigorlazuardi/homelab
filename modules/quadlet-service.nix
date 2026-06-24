# homelab.containers.<name> — the rootless-service pattern as one declarative
# option. Emits: a quadlet container under `srv` (userns=keep-id, hardened,
# loopback-published), an nginx vhost, and tmpfiles for its dirs.
#
# Single-container services only. Multi-container stacks that need a shared
# private network (searxng, immich, observability) stay hand-written because the
# network `.ref` must be taken inside the Home Manager user scope. Single-container
# helpers can now join a shared network via the `networks` knob; only multi-container
# stacks with their OWN private network stay hand-written.
{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    mapAttrs
    mapAttrs'
    nameValuePair
    filterAttrs
    optionalAttrs
    mkMerge
    concatLists
    mapAttrsToList
    ;
  cfg = config.homelab.containers;
  domain = "tigor.web.id";
in
{
  options.homelab.containers = mkOption {
    default = { };
    description = "Rootless podman services (quadlet under srv) with nginx + hardening defaults.";
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }:
        {
          options = {
            image = mkOption {
              type = types.str;
              description = "Container image reference.";
            };
            autoStart = mkOption {
              type = types.bool;
              default = true;
            };
            port = mkOption {
              type = types.nullOr types.port;
              default = null;
              description = "Container port to expose via nginx. null = no ingress.";
            };
            hostPort = mkOption {
              type = types.nullOr types.port;
              default = config.port;
              description = "Host loopback port to publish to (defaults to `port`).";
            };
            subdomain = mkOption {
              type = types.str;
              default = name;
              description = "<subdomain>.${domain} vhost.";
            };
            uid = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "App UID inside the image → keep-id:uid maps it to host srv.";
            };
            gid = mkOption {
              type = types.nullOr types.int;
              default = config.uid;
            };
            user = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Force the container process user (e.g. \"1000:1000\") for images that default to root.";
            };
            userns = mkOption {
              type = types.nullOr types.str;
              default = if config.uid != null then "keep-id:uid=${toString config.uid},gid=${toString config.gid}" else "keep-id";
              description = "Set null to use the default rootless userns (container root → host srv).";
            };
            volumes = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            environments = mkOption {
              type = types.attrsOf types.str;
              default = { };
            };
            environmentFiles = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            harden = mkOption {
              type = types.bool;
              default = true;
              description = "cap-drop all + no-new-privileges. Disable for s6/jlesage images.";
            };
            autoUpdate = mkOption {
              type = types.str;
              default = "registry";
            };
            extraContainerConfig = mkOption {
              type = types.attrs;
              default = { };
              description = "Escape hatch merged into containerConfig.";
            };
            serviceConfig = mkOption {
              type = types.attrs;
              default = { };
              description = "Merged into the generated unit's [Service] (e.g. Slice, CPUWeight, IOWeight for resource caps).";
            };
            nginx.extraConfig = mkOption {
              type = types.lines;
              default = "";
            };
            auth = mkOption {
              type = types.bool;
              default = false;
              description = "Gate the vhost behind tinyauth forward-auth (see services/auth.nix). Whole vhost unless authLocations set.";
            };
            authLocations = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Restrict the auth gate to these locations (e.g. [ \"/\" ] to leave APIs open).";
            };
            tmpfiles = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            networks = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Shared podman network names to join (e.g. [ \"arr\" ]). Resolves peers by container name — see .claude/rules/container-networking.md.";
            };
          };
        }
      )
    );
  };

  config = {
    home-manager.users.srv =
      { config, ... }:
      let
        inherit (config.virtualisation.quadlet) networks;
      in
      {
        virtualisation.quadlet = {
          # Shared network for the media-automation stack (+ jellyfin, seerr,
          # suwayomi). Members opt in with `networks = [ "arr" ]` and address each
          # other by container name (rootless pasta can't hairpin host loopback —
          # see .claude/rules/container-networking.md).
          networks.arr = { };
          containers = mapAttrs (
            _: c: {
              inherit (c) autoStart;
              serviceConfig = lib.mkMerge [
                {
                  Restart = lib.mkDefault "always";
                  RestartSec = lib.mkDefault "10";
                }
                c.serviceConfig
              ];
              containerConfig = mkMerge [
                {
                  inherit (c)
                    image
                    volumes
                    environments
                    environmentFiles
                    autoUpdate
                    ;
                }
                (optionalAttrs (c.userns != null) { inherit (c) userns; })
                (optionalAttrs (c.user != null) { inherit (c) user; })
                (optionalAttrs (c.hostPort != null && c.port != null) {
                  publishPorts = [ "127.0.0.1:${toString c.hostPort}:${toString c.port}" ];
                })
                (optionalAttrs c.harden {
                  noNewPrivileges = true;
                  dropCapabilities = [ "all" ];
                })
                (optionalAttrs (c.networks != [ ]) {
                  networks = map (n: networks.${n}.ref) c.networks;
                })
                c.extraContainerConfig
              ];
            }
          ) cfg;
        };
      };

    services.nginx.virtualHosts = mapAttrs' (
      _: c:
      nameValuePair "${c.subdomain}.${domain}" {
        forceSSL = true;
        tinyauth = {
          enable = c.auth;
          locations = c.authLocations;
        };
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString c.hostPort}";
          extraConfig = c.nginx.extraConfig;
        };
      }
    ) (filterAttrs (_: c: c.port != null) cfg);

    systemd.tmpfiles.rules = concatLists (mapAttrsToList (_: c: c.tmpfiles) cfg);
  };
}
