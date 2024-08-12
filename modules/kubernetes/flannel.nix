{ config
, lib
, ...
}:
with lib;
let
  cfg = config.midugh.k8s-cluster;
  inherit (cfg.nodeConfig) worker;
in
{

  config = mkIf (worker && (cfg.cni == "flannel")) {
    networking = {
      dhcpcd.denyInterfaces = [ "mynet*" "flannel*" ];

      firewall.allowedUDPPorts = [
        8285 # flannel udp
        8472 # flannel vxlan
      ];
    };

    environment.etc."cni/.net.d.wrapped/11-flannel.conflist" = mkIf worker {
      text = builtins.toJSON {
        name = "mynet0";
        cniVersion = "0.3.1";
        plugins = [
          {
            type = "flannel";
            delegate = {
              hairpinMode = true;
              isDefaultGateway = true;
            };
          }
          {
            type = "portmap";
            capabilities.portMappings = true;
          }
        ];
      };
    };

    services.flannel = {
      enable = true;
      network = config.services.kubernetes.clusterCidr;

      storageBackend = "etcd";
    };
  };
}
