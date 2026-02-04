{ nodeConfig
, cluster-config
, pkgs
, lib
, ...
}:
let
  etcdNodes = lib.attrsets.filterAttrs (name: cfg: builtins.elem "master" cfg.roles) cluster-config.nodes;
  etcdScheme = "https";
in
{
  imports = [
    ./secrets.nix
    ./hardware-configuration.nix
  ];

  networking.extraHosts =
    let entries = lib.attrsets.mapAttrsToList (name: cfg:  "${cfg.address}\t${name}") cluster-config.nodes;
    in lib.strings.concatLines entries;

  services.etcd = 
    let
      isInitialNode = builtins.elem nodeConfig.name cluster-config.etcd.initialNodes;
      initialEtcdNodes = lib.attrsets.filterAttrs (name: _: builtins.elem name cluster-config.etcd.initialNodes) etcdNodes;
    in {
      name = nodeConfig.name;
      initialAdvertisePeerUrls = [ "${etcdScheme}://${nodeConfig.address}:2380" ];
      listenPeerUrls = [ "${etcdScheme}://${nodeConfig.address}:2380" ];
      listenClientUrls = [ "${etcdScheme}://${nodeConfig.address}:2379" "${etcdScheme}://127.0.0.1:2379" ];
      advertiseClientUrls = [ "${etcdScheme}://${nodeConfig.address}:2379" ];
      initialCluster = (lib.attrsets.mapAttrsToList (name: cfg: "${name}=${etcdScheme}://${cfg.address}:2380") initialEtcdNodes) ++ (lib.lists.optional (!isInitialNode) "${nodeConfig.name}=${etcdScheme}://${nodeConfig.address}:2380");

      initialClusterState = if isInitialNode then "new" else "existing";
  };
  
  services.kubernetes.apiserver.etcd = 
  {
    servers = lib.attrsets.mapAttrsToList (_: cfg: "${etcdScheme}://${cfg.address}:2379") etcdNodes;
  };

  environment.systemPackages = with pkgs; [
    openssl
    htop
    nload

    traceroute
    tcpdump


    nfs-utils
    dig
    cri-tools
  ];

  environment.sessionVariables = {
    EDITOR = "vim";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch"
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "yes";
    settings.KbdInteractiveAuthentication = false;
  };

  networking = {

    nftables.enable = true;
    hostName = nodeConfig.name;
    interfaces = {
      eth0 = {
        useDHCP = true;
        ipv4.addresses = [
          {
            inherit (nodeConfig) address;
            prefixLength = 24;
          }
        ];
      };
    };
  };

  midugh.kubernetes = {
    enable = true;
    nodeName = nodeConfig.name;
    master.enable = builtins.elem "master" nodeConfig.roles;
    master.schedulable = builtins.elem "worker" nodeConfig.roles;
    pkiLocalDir = "./pki/";
  };

  services.kubernetes.masterAddress = cluster-config.kubernetes.masterAddress;

  system.stateVersion = "25.11";
}
