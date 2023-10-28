{
    description = "A very basic flake";

    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    outputs = {
        nixpkgs,
        ...
    }:
let authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch" ];
    gatewayAddress = "192.168.2.5";
    getAddress = n: 
        let subnetPrefix = "10.200.0";
        in "${subnetPrefix}.${builtins.toString n}";
    suffixAddress = addr: "${addr}/32";
    masterAddress = getAddress 1;
    subnet = getAddress 0 + "/24";
    createKubeNode = hostName: address: {
        nixpkgs.localSystem.system = "aarch64-linux";
        imports = [
            ./rpi-cluster
        ];
        deployment.targetHost = address;
        services.rpi-wireguard = {
            externalInterface = "end0";
            internalInterfaces.wg0 = {
                privateKeyFile = "/root/wireguard-keys/private";
                ips = [ (suffixAddress address) ];

                peers.gateway = {
                    allowedIPs = [ subnet ];
                    publicKey = "RaNaggBzoh18jWNYafs8aV4eCvcltg+JUz4Qd47unCQ=";
                    endpoint = "${gatewayAddress}:51820";
                };
            };
        };

        midugh.rpi-config = {
            inherit hostName;
            ssh.authorizedKeys = authorizedKeys;
        };
        services.rpi-kubernetes = {
            network = {
                address = address;
            };

            kubernetesConfig.api = {
                inherit masterAddress;
            };

            dns.enable = true;
        };
    };
    in {
        nixopsConfigurations.default =
        let inherit (nixpkgs) lib;
        in {
            inherit nixpkgs;
            network = {
                storage.legacy = {
                    databasefile = "~/.nixops/deployments.nixops";
                };
                description = "cluster";
            };
            cluster-master =
            let address = masterAddress;
                hostName = "cluster-master";
            in {
                nixpkgs.localSystem.system = "aarch64-linux";
                deployment.targetHost = address;
                imports = [
                    ./rpi-cluster
                ];

                services.rpi-wireguard = {
                    enable = true;
                    isServer = true;
                    externalInterface = "end0";
                    internalInterfaces.wg0 = {
                        ips = [ "${address}/24" ];
                        privateKeyFile = "/root/wireguard-keys/private";

                        peers.cluster-node-1 = {
                            publicKey = "AQJjXBXb2pkIWQdX2YnArOClHOcdLqZRUslTkpYtTzU=";
                            allowedIPs = [ (suffixAddress (getAddress 2)) ];
                        };

                        peers.cluster-node-2 = {
                            publicKey = "38qdBG92oCCWnlc3aPEI9uOIkamXIulgk9QRkk5ez3Q=";
                            allowedIPs = [ (suffixAddress (getAddress 3)) ];
                        };

                        peers.cluster-node-3 = {
                            publicKey = "lxwDeBV8eh9JkOjuhpMFuGArpMaeF2+PhB0oHHK+ZQs=";
                            allowedIPs = [ (suffixAddress (getAddress 4)) ];
                        };

                        peers.midugh-pc = {
                            publicKey = "5YtnXbwCv8i0Vy2WPo1DgM4fYgXib25tnRKVHPRz7m0=";
                            allowedIPs = [ (suffixAddress (getAddress 42)) ];
                        };
                    };
                };

                networking.firewall.allowedTCPPorts = [
                    2049 # nfs server
                    9100 # prometheus
                ];

                services.forward-proxy = {
                    enable = true;
                    hosts."grafana.cluster.local" = {
                        forceSsl = false;
                        proxyUrl = "http://${address}:30792";
                    };
                };
                midugh.rpi-config = {
                    inherit hostName;
                    ssh.authorizedKeys = authorizedKeys;
                };
                services.rpi-kubernetes = {
                    enable = true;
                    network = {
                        inherit address;
                    };

                    kubernetesConfig.roles = ["master" "node"];
                    kubernetesConfig.api = {
                        allowPrivileged = true;
                        port = 6443;
                    };

                    dns.enable = true;
                    etcd.port = 2379;
                };

                fileSystems."/nfs" = {
                    device = "/dev/sda";
                    options = [ "bind" ];
                };

                services.nfs.server = {
                    enable = true;
                    exports = ''
                        /nfs ${subnet}(rw,no_subtree_check,fsid=0)
                        /nfs/promdata ${subnet}(rw,nohide,insecure,no_subtree_check)
                        /nfs/grafana ${subnet}(rw,nohide,insecure,no_subtree_check)
                    '';
                    extraNfsdConfig = ''
                    vers3=no
                    '';
                };
                services.rpcbind.enable = lib.mkForce false;
            };
            cluster-node-1 = createKubeNode "cluster-node-1" (getAddress 2);
            cluster-node-2 = createKubeNode "cluster-node-2" (getAddress 3);
            cluster-node-3 = createKubeNode "cluster-node-3" (getAddress 4);
            };
    };
}
