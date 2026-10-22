{ ... }:
{
  # Placeholder — replace with the real hardware configuration once
  # cluster-router (raspi4 4G) is imaged and `nixos-generate-config` has
  # been run against it, or with the equivalent raspi4 boot config.

  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.grub.enable = false;

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
}
