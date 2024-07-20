{
  sops.defaultSopsFile = ../secrets/secrets.yaml;

  sops.age.sshKeyPaths = [
    ../secrets/servers.key
  ];
}
