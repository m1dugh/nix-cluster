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
        master = mkOption {
            description = "Whether the node is a master or not";
            type = types.bool;
            default = false;
        };

        worker = mkOption {
            description = "Whether the node is a worker node or not";
            type = types.bool;
            default = true;
        };

        kubeMasterAddress = mkOption {
            description = "The address of the master node";
            type = types.str;
        };

        kubeMasterAPIServerPort = mkOption {
            description = "The port of the api server on the master";
            default = 6443;
        };

        etcd = mkOption {
            default = {
                enable = false;
            };
            type = types.submodule ({...}: {
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

    assertions = [
        {
            assertion = (with cfg; master || worker);
            message = "The node must be at least master or worker node";
        }
    ];

    services.kubernetes = 
    let roles =
    lists.optional cfg.master "master"
    ++ lists.optional cfg.worker "node";
        apiserverAddress = with cfg; "https://${kubeMasterAddress}:${toString kubeMasterAPIServerPort}";
    in (lib.mkMerge [{
        inherit roles apiserverAddress;
        masterAddress = cfg.kubeMasterAddress;
        kubelet.extraOpts = "--fail-swap-on=false";

        easyCerts = true;

        addons.dns = {
            enable = true;
            coredns = {
                finalImageTag = "1.10.1";
                imageDigest = "sha256:a0ead06651cf580044aeb0a0feba63591858fb2e43ade8c9dea45a6a89ae7e5e";
                imageName = "coredns/coredns";
                sha256 = "sha256-wYMJV/rtUDQXUq5W5WaxzTLrYPtCiVIOVbVqIJJJ5nE=";
            };
        };
    }
    (mkIf cfg.master {
        apiserver = {
            securePort = cfg.kubeMasterAPIServerPort;
            advertiseAddress = cfg.kubeMasterAddress;
        };
    })
    # If not master, then it has to be a worker node
    (mkIf (! cfg.master) {
        kubelet.kubeconfig.server = apiserverAddress;
    })
    ]);

    # services.etcd = 
    # let scheme = if cfg.etcd.tls.enable then "https" else "http";
    # inherit (cfg.etcd) config extraNodes tls;
    # initialCluster = ["${config.name}=${scheme}://${config.address}:${config.port}"]
    #     ++ builtins.map (c: "${c.name}=${scheme}://${c.address}:${c.port}") extraNodes;
    # in mkIf cfg.etcd.enable (lib.mkMerge [{
    #     inherit initialCluster;

    #     enable = true;
    #     initialAdvertisePeerUrls = client.address;
    #     listenPeerUrls = client.address;
    #     listenClientUrls = "${client.address},${scheme}://127.0.0.1:${client.port}";
    #     advertiseClientUrls = client.address;
    # }
    # (mkIf tls.enable {
    #     clientCertAuth = true;
    #     peerClientCertAuth = true;
    #     inherit (tls) trustedCaFile certFile keyFile peerTrustedCaFile peerCertFile peerKeyFile;
    # })
    # ]);
   };
}
