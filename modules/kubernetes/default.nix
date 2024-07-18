{
    config,
    options,
    lib,
    ...
}:
with lib;
let cfg = config.midugh.k8s-cluster;
inherit ((import ./lib.nix).types) etcdHostType;
    tlsConfigType = types.submodule {
        options = {
            enable = mkEnableOption "TLS for etcd cluster";
            trustedCaFile = mkOption {
                type = types.path;
                description = "The path to the trusted ca file";
            };

            certFile = mkOption {
                type = types.path;
                description = "The path to the trusted cert file";
            };
            keyFile = mkOption {
                type = types.path;
                description = "The path to the trusted key file";
            };

            peerTrustedCaFile = mkOption {
                type = types.path;
                description = "The path to the peer trusted ca file";
            };
            peerCertFile = mkOption {
                type = types.path;
                description = "The path to the peer trusted cert file";
            };
            peerKeyFile = mkOption {
                type = types.path;
                description = "The path to the peer trusted key file";
            };
        };
    };
in {
   options.midugh.k8s-cluster = { 
        enable = mkEnableOption "kubernetes overlay";
        roles = options.services.kubernetes.roles;

        etcd = mkOption {
            type = types.submodule ({}: {
                options = {
                    enable = mkEnableOption "node as part of the etcd cluster";
                    tls = mkOption {
                        description = "The tls options";
                        type = tlsConfigType;
                    };

                    config = mkOption {
                        type = etcdHostType;
                        description = "The config for this node";
                    };

                    extraNodes = mkOption {
                        type = types.listOf etcdHostType;
                        description = "Extra hosts that are in the cluster";
                        default = [];
                        example = literalExpression ''
                            [
                                {
                                    name = "infra0";
                                    address = "https://10.10.10.10:2379";
                                }
                            ]
                        '';
                    };
                };
            });
        };
   };

   config = mkIf cfg.enable {
    services.kubernetes = {
        enable = true;
    };

    services.etcd = 
    let scheme = if cfg.etcd.tls.enable then "https" else "http";
    inherit (cfg.etcd) config extraNodes tls;
    initialCluster = ["${config.name}=${scheme}://${config.address}:${config.port}"]
        ++ builtins.map (c: "${c.name}=${scheme}://${c.address}:${c.port}") extraNodes;
    in mkIf cfg.etcd.enable (lib.mkMerge [{
        inherit initialCluster;

        enable = true;
        initialAdvertisePeerUrls = client.address;
        listenPeerUrls = client.address;
        listenClientUrls = "${client.address},${scheme}://127.0.0.1:${client.port}";
        advertiseClientUrls = client.address;
    }
    (mkIf tls.enable {
        clientCertAuth = true;
        peerClientCertAuth = true;
        inherit (tls) trustedCaFile certFile keyFile peerTrustedCaFile peerCertFile peerKeyFile;
    })
    ]);
   };
}
