# Samba — network file sharing (native). Exposes the disks + the new /srv/data
# tree. Set the smb password manually: `smbpasswd -a homeserver`.
{
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "homeserver";
        "netbios name" = "homeserver";
        security = "user";
        "hosts allow" = "192.168.0. 192.168.100. 10.0.0. 10.88. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      nas = {
        path = "/var/mnt/nas";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "force user" = "homeserver";
        "force group" = "homeserver";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      wolf = {
        path = "/var/mnt/wolf";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "force user" = "homeserver";
        "force group" = "homeserver";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      # The rootless-services data tree. force group media so files stay
      # group-accessible to the services (srv) and the human user.
      data = {
        path = "/srv/data";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "force user" = "homeserver";
        "force group" = "media";
        "create mask" = "0664";
        "directory mask" = "2775";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
