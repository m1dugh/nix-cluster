{ pkgs
, config
, lib
, ...
}:
with lib;
let
  top = config.midugh.k8s-cluster;
  cfg = top.coredns;
  inherit (top.nodeConfig) worker address;
  inherit (top) apiserver;
  inherit ((pkgs.callPackage ./lib.nix { }).lib) mkCoreDnsCert;
in
{
options.midugh.k8s-cluster.coredns.forwarder = mkOption {
    type = types.str;
    default = "1.1.1.1";
    description = ''
        An external forwarder for the dns server
        '';
    example = "8.8.8.8";
};
  config = mkIf (top.enable && worker) {
    services.coredns = {
      enable = true;
      config = ''
        .:53 {
            kubernetes cluster.local {
                endpoint https://${apiserver.address}:${toString apiserver.port}
                tls ${mkCoreDnsCert "coredns.pem"} ${mkCoreDnsCert "coredns-key.pem"} ${mkCoreDnsCert "ca.pem"}
                pods verified
            }
            forward . ${cfg.forwarder}:53
        }
      '';
    };

    services.kubernetes.kubelet.clusterDns = address;

    networking.firewall.allowedUDPPorts = [ 53 ];

    users.groups.coredns = {
        gid = 993;
    };
    users.users.coredns = {
      group = config.users.groups.coredns.name;
      uid = config.users.groups.coredns.gid;
      isSystemUser = true;
    };
  };
}
