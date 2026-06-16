# Auth stack. tinyauth is the nginx forward-auth proxy + login UI; it brokers
# through dex (OIDC) to pocket-id (the passkey IdP / user store). All three run
# rootless under srv via the homelab.containers helper.
#
# This module also DECLARES a per-vhost `tinyauth` option on every nginx vhost,
# so any service (helper-made or hand-written) can gate itself:
#   - helper services:  set `auth = true;` (and optionally `authLocations`).
#   - hand-written:      set `services.nginx.virtualHosts.<h>.tinyauth.enable = true;`.
{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    length
    genAttrs
    optionalAttrs
    mkIf
    ;

  authDomain = "auth.tigor.web.id";
  authHostPort = 3001; # tinyauth loopback port (host 3000 is AdGuard's LAN UI)
  appURL = "https://${authDomain}";
  # nginx auth_request subrequest target (rootless → loopback).
  authEndpoint = "http://127.0.0.1:${toString authHostPort}/api/auth/nginx";
in
{
  # ---- per-vhost forward-auth option (merges onto the nginx vhost submodule) ----
  options.services.nginx.virtualHosts = mkOption {
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        {
          options.tinyauth = {
            enable = mkOption {
              type = types.bool;
              default = (length config.tinyauth.locations) > 0;
              description = "Protect this vhost with tinyauth. No locations + enable = protect everything.";
            };
            locations = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Specific locations to protect. Empty + enable = whole vhost.";
            };
          };
          config = {
            # Protect-everything: auth_request at the server level.
            extraConfig =
              mkIf (config.tinyauth.enable && (length config.tinyauth.locations == 0))
                # nginx
                ''
                  auth_request /tinyauth;
                  error_page 401 = @tinyauth_login;
                '';
            # https://tinyauth.app/docs/guides/nginx-proxy-manager.html
            locations =
              optionalAttrs config.tinyauth.enable {
                "/tinyauth" = {
                  proxyPass = authEndpoint;
                  extraConfig = # nginx
                    ''
                      internal;
                      proxy_set_header X-Forwarded-Proto $scheme;
                      proxy_set_header X-Forwarded-Host $http_host;
                      proxy_set_header X-Forwarded-Uri $request_uri;
                    '';
                };
                "@tinyauth_login".extraConfig = # nginx
                  ''
                    return 302 ${appURL}/login?redirect_uri=$scheme://$http_host$request_uri;
                  '';
              }
              // genAttrs config.tinyauth.locations (_loc: {
                extraConfig = # nginx
                  ''
                    auth_request /tinyauth;
                    error_page 401 = @tinyauth_login;
                    auth_request_set $tinyauth_remote_user $upstream_http_remote_user;
                    auth_request_set $tinyauth_remote_groups $upstream_http_remote_groups;
                    auth_request_set $tinyauth_remote_email $upstream_http_remote_email;
                    proxy_set_header Remote-User $tinyauth_remote_user;
                    proxy_set_header Remote-Groups $tinyauth_remote_groups;
                    proxy_set_header Remote-Email $tinyauth_remote_email;
                  '';
              });
          };
        }
      )
    );
  };

  config = {
    sops.secrets = {
      # Read by podman (srv) at container start / mount time.
      "tinyauth.env" = {
        sopsFile = ../secrets/tinyauth.env;
        format = "dotenv";
        key = "";
        owner = "srv";
      };
      "pocket-id.env" = {
        sopsFile = ../secrets/pocket-id.env;
        format = "dotenv";
        key = "";
        owner = "srv";
      };
      "dex.yaml" = {
        sopsFile = ../secrets/dex.yaml;
        format = "yaml";
        key = "";
        owner = "srv";
      };
    };

    homelab.containers = {
      # Forward-auth proxy + login UI.
      tinyauth = {
        image = "ghcr.io/steveiliop56/tinyauth:v4";
        port = 3000;
        hostPort = authHostPort;
        subdomain = "auth";
        environments = {
          APP_TITLE = "Homeserver";
          APP_URL = appURL;
          OAUTH_AUTO_REDIRECT = "dex";
          SECURE_COOKIES = "true";
          PROVIDERS_DEX_NAME = "dex";
          PROVIDERS_DEX_AUTH_URL = "https://dex.tigor.web.id/auth";
          PROVIDERS_DEX_TOKEN_URL = "https://dex.tigor.web.id/token";
          PROVIDERS_DEX_USER_INFO_URL = "https://dex.tigor.web.id/userinfo";
          PROVIDERS_DEX_SCOPES = "openid,profile,email";
          PROVIDERS_DEX_REDIRECT_URL = "${appURL}/api/oauth/callback/dex";
          SESSION_EXPIRY = toString (24 * 60 * 60 * 30); # 30 days
        };
        environmentFiles = [ config.sops.secrets."tinyauth.env".path ];
        volumes = [ "/srv/data/state/tinyauth:/data" ];
        tmpfiles = [ "d /srv/data/state/tinyauth 0750 srv srv -" ];
      };

      # Passkey IdP / user store.
      pocket-id = {
        image = "ghcr.io/pocket-id/pocket-id:v2";
        port = 1411;
        subdomain = "id";
        environments = {
          APP_URL = "https://id.tigor.web.id";
          TRUST_PROXY = "true";
        };
        environmentFiles = [ config.sops.secrets."pocket-id.env".path ];
        volumes = [ "/srv/data/state/pocket-id:/app/data" ];
        tmpfiles = [ "d /srv/data/state/pocket-id 0750 srv srv -" ];
      };

      # OIDC broker between tinyauth and pocket-id. Runs as uid 1001 → keep-id
      # maps it to host srv, so /srv/data/state/dex and the mounted config (owned
      # srv) are readable.
      dex = {
        image = "ghcr.io/dexidp/dex:v2.37.0";
        port = 5556;
        subdomain = "dex";
        uid = 1001;
        volumes = [
          "/srv/data/state/dex:/var/lib/dex"
          "${config.sops.secrets."dex.yaml".path}:/etc/dex/config.yaml:ro"
        ];
        extraContainerConfig.exec = "dex serve /etc/dex/config.yaml";
        tmpfiles = [ "d /srv/data/state/dex 0750 srv srv -" ];
      };
    };
  };
}
