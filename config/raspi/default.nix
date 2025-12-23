{ pkgs
, ...
}:
{
    hardware = {
        raspberry-pi."4".apply-overlays-dtmerge.enable = true;
        deviceTree = {
            enable = true;
            filter = "*rpi-4-*.dtb";
        };
    };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    autoResize = true;
  };

    environment.systemPackages = with pkgs; [
        libraspberrypi
        raspberrypi-eeprom
    ];

  boot.growPartition = true;
  boot.loader.timeout = 1;
}
