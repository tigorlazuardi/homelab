# Standalone disko config for fenrir HDD only
{
  disko.devices.disk.fenrir = {
    type = "disk";
    device = "/dev/disk/by-id/ata-ST4000VN006-3CW104_WW68SEMC"; # Seagate 4TB HDD
    content = {
      type = "gpt";
      partitions = {
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "/data" = {
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
                mountpoint = "/var/mnt/fenrir";
              };
              "/data/.snapshots" = { };
            };
          };
        };
      };
    };
  };
}
