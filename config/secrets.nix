{
  sops.defaultSopsFile = ../secrets/secrets.yaml;

  sops.age.sshKeyPaths = [
    "/var/lib/nixos/servers.key"
  ];
}
