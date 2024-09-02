{ colmena ? false
, lib
, ...
}:
with lib;
{
  imports = [
    ./coredns.nix
    ./master.nix
    ./etcd.nix
    ./worker.nix
  ];

  deployment.keys."servers.key" = mkIf colmena {
    keyFile = ../../secrets/servers.key;
    destDir = "/var/lib/nixos/";
    group = "root";
    user = "root";
    permissions = "0400";
  };
}
