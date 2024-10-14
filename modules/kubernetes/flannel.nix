{ config
, lib
, pkgs
, ...
}:
with lib;
let
  inherit (pkgs.callPackage ../../lib { }) getEtcdNodes mkEtcdEndpoint;
  cfg = config.midugh.k8s-cluster;
  inherit (cfg.nodeConfig) worker master;
  inherit ((pkgs.callPackage ./lib.nix { }).lib) mkFlannelCert;
  k8sNode = worker || master;
  etcdNodes = getEtcdNodes cfg.clusterNodes;
  etcdEndpoints = builtins.map mkEtcdEndpoint etcdNodes;
in
{

  config = mkIf k8sNode {
    networking = {
      dhcpcd.denyInterfaces = [ "mynet*" "flannel*" ];

      firewall.allowedUDPPorts = [
        8285 # flannel udp
        8472 # flannel vxlan
      ];
    };

    services.flannel = {
      enable = true;
      network = config.services.kubernetes.clusterCidr;

      storageBackend = "etcd";
      etcd = {
          endpoints = etcdEndpoints;
          keyFile = mkFlannelCert "etcd-client-key.pem";
          certFile = mkFlannelCert "etcd-client.pem";
          caFile = mkFlannelCert "etcd-ca.pem";
      };
    };
  };
}
