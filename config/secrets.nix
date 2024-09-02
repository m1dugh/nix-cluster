{ colmena ? false
, lib
, ...
}:
with lib;
{
  sops.defaultSopsFile = ../secrets/secrets.yaml;

  sops.age.sshKeyPaths =
    let
      key =
        if colmena then
          "/var/lib/nixos/servers.key"
        else
          ../secrets/servers.key
      ;
    in
    lists.singleton key;
}
