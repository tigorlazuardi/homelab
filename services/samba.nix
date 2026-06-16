# Samba — network file sharing (native). Exposes the storage-tier disks. Files
# are forced to group `media` (setgid 2775) so SMB writes stay accessible to the
# rootless services (srv). Set the smb password manually: `smbpasswd -a homeserver`.
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
      # nas (dying HDD) — disposable downloads.
      nas = {
        path = "/var/mnt/nas";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "force user" = "homeserver";
        "force group" = "media";
        "create mask" = "0664";
        "directory mask" = "2775";
      };
      # wolf (HDD) — durable replaceable media + arr downloads.
      wolf = {
        path = "/var/mnt/wolf";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "force user" = "homeserver";
        "force group" = "media";
        "create mask" = "0664";
        "directory mask" = "2775";
      };
      # fenrir (HDD) — sentimental / irreplaceable (immich, paperless docs).
      fenrir = {
        path = "/var/mnt/fenrir";
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
