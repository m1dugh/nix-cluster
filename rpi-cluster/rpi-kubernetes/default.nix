{
    config,
    pkgs,
    lib,
    ...
}:
with lib;
let ismaster = elem "master" cfg.kubernetesConfig.roles;
    isnode = elem "node" cfg.kubernetesConfig.roles;
    cfg = config.services.rpi-kubernetes;
    mkNetworkSettings = {
        address = mkOption {
            description = "ipv4 address of node";
            type = types.str;
        };

        localAddress = mkOption {
            description = "The ipv4 on the network with internet connection";
            type = types.str;
            # Forces usage for master only.
            default = if ismaster then null else "";
        };

        hostname = mkOption {
            description = "hostname of the node";
            type = types.nullOr types.str;
            default = null;
        };

    };

    mkEtcdConfig = {
        port = mkOption {
            description = "Port for etcd server";
            type = types.int;
            default = 2379;
        };
    };

    mkKubernetesConfig = {
        roles = mkOption {
            description = "The roles to apply to the node";
            type = types.listOf types.str;
            default = [ "node" ];
        };

        api = {
            port = mkOption {
                description = "The port of the kubernetes api on the master";
                type = types.int;
                default = 6443;
            };

            allowPrivileged = mkOption {
                description = "Whether to allow privileged containers on the cluster";
                type = types.bool;
                default = false;
            };

            masterAddress = mkOption {
                description = "The ip address of the master";
                type = types.str;
                default = if ismaster then cfg.network.address else null;
            };

            masterHostname = mkOption {
                description = "The network hostname of the master";
                type = types.nullOr types.str;
                default = "cluster-master";
            };
        };
    };

    masterAddress = (if ismaster then cfg.network.address else cfg.kubernetesConfig.api.masterAddress);
    apiUrl = "https://${masterAddress}:${toString cfg.kubernetesConfig.api.port}";

    mkDnsConfig = {
        enable = mkOption {
            type = types.bool;
            default = false;
        };
    };
in {
    imports = [
        <nixpkgs/nixos/modules/installer/sd-card/sd-image.nix>
    ];
    options.services.rpi-kubernetes = {
        enable = mkEnableOption "rpi-kubernetes";
        network = mkNetworkSettings;
        kubernetesConfig = mkKubernetesConfig;
        dns = mkDnsConfig;
        etcd = mkEtcdConfig;
    };
    config = mkIf cfg.enable (mkMerge ([
        {
# Required kubernetes packages
            environment.systemPackages = with pkgs; [
                kompose
                kubectl
                kubernetes

                cfssl
                openssl
            ];

        }
        {
            networking.firewall = {
                allowedTCPPorts =
                (lists.optionals ismaster [
                    cfg.etcd.port
                    cfg.kubernetesConfig.api.port
                    8888 # flannel port
                    10259 # kube scheduler
                    10257 # kube-controller-manager
                    10250 # kubelet api
                ]) ++
                (lists.optional isnode 10250);
            };

# ETCD fix on ARM devices.
            services.etcd.extraConf.UNSUPPORTED_ARCH = "arm64";
            services.kubernetes = {
                masterAddress = masterAddress;
                roles = cfg.kubernetesConfig.roles;
                apiserverAddress = apiUrl;

                pki = 
                let 
                inherit (cfg.kubernetesConfig.api) masterHostname masterAddress;
                inherit (cfg.network) address;
                in {
                    cfsslAPIExtraSANs = (builtins.filter (v: v != null) [ masterHostname masterAddress address ]);
                };
                addons.dns = {
                    enable = cfg.dns.enable;
                    coredns = {
                        finalImageTag = "1.10.1";
                        imageDigest = "sha256:a0ead06651cf580044aeb0a0feba63591858fb2e43ade8c9dea45a6a89ae7e5e";
                        imageName = "coredns/coredns";
                        sha256 = "0c4vdbklgjrzi6qc5020dvi8x3mayq4li09rrq2w0hcjdljj0yf9";
                    };
                };
            };
        }
        (mkIf ismaster {
            services.kubernetes.apiserver = 
            let inherit (cfg.kubernetesConfig) api;
            in {
                inherit (api) allowPrivileged;
                enable = true;
                securePort = api.port;
                advertiseAddress = cfg.network.address;
            };

            services.etcd = 
            let inherit (cfg.network) address;
                inherit (cfg.etcd) port;
            in {
                listenClientUrls = ["http://${address}:${toString port}"];
                advertiseClientUrls = ["http://${address}:${toString port}"];
            };
        })

        (mkIf isnode {
            services.kubernetes.kubelet.kubeconfig.server = apiUrl;
        })
    ]));
}
