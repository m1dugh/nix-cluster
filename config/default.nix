{ nodeConfig
, apiserver
, pkgs
, clusterNodes
, lib
, ...
}:
with lib;
{
  imports = [
    ./secrets.nix
    ./hardware-configuration.nix
  ];

  environment.systemPackages = with pkgs; [
    openssl
    htop
    nload
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
    extraHosts =
    let
        entries = map ({name, address, ...}: "${address}   ${name}") clusterNodes;
    in strings.concatStringsSep "\n" entries;

    nftables.enable = true;
    hostName = nodeConfig.name;
    defaultGateway = {
      address = "192.168.1.1";
    };
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

  midugh.k8s-cluster = {
    enable = true;
    cni = "calico";
    inherit nodeConfig clusterNodes apiserver;
  };

  system.stateVersion = "24.05";
}
