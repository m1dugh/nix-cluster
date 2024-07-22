{ ...
}:
{
  hardware.raspberry-pi."4".leds = {
    eth.disable = true;
    act.disable = true;
    pwr.disable = true;
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    autoResize = true;
  };

  boot.growPartition = true;
  boot.loader.timeout = 1;
}
