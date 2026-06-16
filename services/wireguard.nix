# WireGuard VPN server (native). Remote access path into the box.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  externalInterface = "eth0";
  clients = [
    {
      name = "oppo-find-x8";
      address = "10.0.0.2/32";
      privateKey = config.sops.placeholder."wireguard/clients/oppo-find-x8/private_key";
    }
    {
      name = "envy";
      address = "10.0.0.3/32";
      privateKey = config.sops.placeholder."wireguard/clients/envy/private_key";
    }
  ];
  serverPublicKey = config.sops.placeholder."wireguard/server/public_key";
  endpoint = "103.156.119.209:51820";
  dns = "10.0.0.1"; # AdGuard on the wg gateway
in
{
  environment.systemPackages = [ pkgs.wireguard-tools ];

  sops.secrets =
    let
      opts.sopsFile = ../secrets/wireguard.yaml;
    in
    lib.genAttrs [
      "wireguard/server/private_key"
      "wireguard/server/public_key"
      "wireguard/clients/oppo-find-x8/private_key"
      "wireguard/clients/envy/private_key"
    ] (_: opts);

  # Client configs rendered to /var/lib/wireguard-configs (used by the auth-gated
  # download page restored in the auth wave — see TODO below).
  sops.templates = builtins.listToAttrs (
    map (client: {
      name = "wireguard-client-${client.name}.conf";
      value = {
        owner = "nginx";
        group = "nginx";
        mode = "0440";
        content = ''
          [Interface]
          PrivateKey = ${client.privateKey}
          Address = ${client.address}
          DNS = ${dns}

          [Peer]
          PublicKey = ${serverPublicKey}
          Endpoint = ${endpoint}
          AllowedIPs = 0.0.0.0/0
          PersistentKeepalive = 25
        '';
      };
    }) clients
  );

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
    trustedInterfaces = [ "wg0" ];
    checkReversePath = "loose";
  };

  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = [ "wg0" ];
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.0.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/server/private_key".path;
    postSetup = ''
      ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o ${externalInterface} -j MASQUERADE
    '';
    postShutdown = ''
      ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o ${externalInterface} -j MASQUERADE
    '';
    peers = [
      {
        publicKey = "LPnjJF6iGnzeZA8i4kmjQU3b2fKU7u35uqGBQ0cSCnY="; # oppo-find-x8
        allowedIPs = [ "10.0.0.2/32" ];
      }
      {
        publicKey = "wNG7mSjPZgkNSXkdmPGOFGl6jNEfvs+cglkTbxdCMz4="; # envy
        allowedIPs = [ "10.0.0.3/32" ];
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/wireguard-configs 0750 nginx nginx -"
  ]
  ++ map (
    client:
    "L+ /var/lib/wireguard-configs/${client.name}.conf - - - - ${
      config.sops.templates."wireguard-client-${client.name}.conf".path
    }"
  ) clients;

  # TODO(auth wave): restore wg.tigor.web.id config-download page BEHIND AUTH.
  # It serves client private keys, so it must never be unauthenticated.
}
