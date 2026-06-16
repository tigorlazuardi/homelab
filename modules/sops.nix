{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];
  environment.systemPackages = with pkgs; [
    sops
    age
  ];

  # Tells the sops binary where to find the private age key file for decryption.
  environment.variables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
  # This has to point to a filesystem that is mounted early, e.g. root filesystem so
  # the secrets can be decrypted during boot.
  #
  # Do not use $HOME/.config/sops/age/key.txt or similar paths that depend on user home directories.
  #
  # Also use /opt so no conflicts with /etc or /var
  #
  # Ensure the file is readable by the user (for creating/editing secrets) and only by root. perm 0400, owned by $USER.
  #
  # On nixos installation, you can place the key here manually to install with secrets available.
  sops.age.keyFile = "/opt/age-key.txt";
}
