{ lib
, ...
}:
{
  swapDevices = lib.mkForce [ ];

  boot.kernelParams = [
    "cgroup_enable=cpuset"
    "cgroup_enable=memory"
    "cgroup_memory=1"
  ];
}
