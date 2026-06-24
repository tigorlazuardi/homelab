{
  # Port not reachable from internet (router blocks); remote access via WireGuard.
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      # Don't reverse-resolve the connecting client. The host's resolver is its own
      # AdGuard (192.168.100.5); when AdGuard is down a PTR lookup blocks and
      # incoming SSH hangs even by IP. UseDNS=no makes sshd immune to DNS state.
      UseDns = false;
    };
  };
}
