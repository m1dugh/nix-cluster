{
    pkgs,
    config,
    lib,
    ...
}:
with lib;
let
    top = config.midugh.k8s-cluster;
    inherit (top.nodeConfig) worker address;
    inherit (top) apiserver;
    inherit ((pkgs.callPackage ./lib.nix {}).lib) mkCoreDnsCert;
in {
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
                    forward . 1.1.1.1:53
                }
            '';
        };

        services.kubernetes.kubelet.clusterDns = address;

        networking.firewall.allowedUDPPorts = [ 53 ];

        users.groups.coredns = {};
        users.users.coredns = {
            group = config.users.groups.coredns.name;
            isSystemUser = true;
        };
    };
}
