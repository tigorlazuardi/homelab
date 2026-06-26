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

  # Client configs rendered to /var/lib/wireguard-configs (served by the
  # tinyauth-gated download page below).
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

  # Config-download page — serves client private keys, so it is gated behind
  # tinyauth forward-auth (never unauthenticated).
  services.nginx.virtualHosts."wg.tigor.web.id" =
    let
      configDir = "/var/lib/wireguard-configs";
      clientLinks = lib.concatMapStringsSep "\n" (client: ''
        <div class="client">
          <h2>${client.name}</h2>
          <div class="qr" id="qr-${client.name}"></div>
          <a href="/configs/${client.name}.conf" download="${client.name}.conf">Download Config</a>
        </div>
      '') clients;
      webroot = pkgs.writeTextDir "index.html" ''
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>WireGuard Configs</title>
          <script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
          <style>
            body { font-family: system-ui, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; background: #1a1a2e; color: #eee; }
            h1 { color: #88d498; }
            .client { background: #16213e; border-radius: 8px; padding: 16px; margin: 16px 0; }
            .qr { background: #fff; display: inline-block; padding: 8px; border-radius: 4px; }
            a { display: inline-block; margin-top: 8px; padding: 8px 16px; background: #88d498; color: #16213e; text-decoration: none; border-radius: 4px; font-weight: 600; }
            a:hover { background: #6ab57a; }
          </style>
        </head>
        <body>
          <h1>WireGuard Client Configs</h1>
          ${clientLinks}
          <script>
            async function loadQR(name) {
              const res = await fetch('/configs/' + name + '.conf');
              const text = await res.text();
              const qr = qrcode(0, 'M');
              qr.addData(text);
              qr.make();
              document.getElementById('qr-' + name).innerHTML = qr.createImgTag(4);
            }
            ${lib.concatMapStringsSep "\n" (client: "loadQR('${client.name}');") clients}
          </script>
        </body>
        </html>
      '';
    in
    {
      forceSSL = true;
      tinyauth.enable = true;
      root = webroot;
      locations = {
        "/".index = "index.html";
        "/configs/" = {
          alias = "${configDir}/";
          extraConfig = "default_type application/octet-stream;";
        };
      };
    };
}
