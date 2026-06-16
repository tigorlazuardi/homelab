# homelab.containers.<name> — the rootless-service pattern as one declarative
# option. Emits: a quadlet container under `srv` (userns=keep-id, hardened,
# loopback-published), an nginx vhost, and tmpfiles for its dirs.
#
# Single-container services only. Multi-container stacks that need a shared
# private network (searxng, immich, observability) stay hand-written because the
# network `.ref` must be taken inside the Home Manager user scope.
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
            nginx.extraConfig = mkOption {
              type = types.lines;
              default = "";
            };
            tmpfiles = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
          };
        }
      )
    );
  };

  config = {
    home-manager.users.srv.virtualisation.quadlet.containers = mapAttrs (
      _: c: {
        inherit (c) autoStart;
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
          (optionalAttrs (c.hostPort != null && c.port != null) {
            publishPorts = [ "127.0.0.1:${toString c.hostPort}:${toString c.port}" ];
          })
          (optionalAttrs c.harden {
            noNewPrivileges = true;
            dropCapabilities = [ "all" ];
          })
          c.extraContainerConfig
        ];
      }
    ) cfg;

    services.nginx.virtualHosts = mapAttrs' (
      _: c:
      nameValuePair "${c.subdomain}.${domain}" {
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString c.hostPort}";
          extraConfig = c.nginx.extraConfig;
        };
      }
    ) (filterAttrs (_: c: c.port != null) cfg);

    systemd.tmpfiles.rules = concatLists (mapAttrsToList (_: c: c.tmpfiles) cfg);
  };
}
