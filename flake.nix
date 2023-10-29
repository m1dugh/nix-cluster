{
    description = "A very basic flake";

    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    outputs = {
        nixpkgs,
        ...
    }:
let authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch" ];
    defaultDNS = [ "192.168.1.1" ];
    gatewayAddress = "192.168.2.5";
    dnsSubnet = "cluster.local";
    getAddress = n: 
        let subnetPrefix = "10.200.0";
        in "${subnetPrefix}.${builtins.toString n}";
    suffixAddress = addr: "${addr}/32";
    masterAddress = getAddress 1;
    subnet = getAddress 0 + "/24";
    ipv4Gateway = "192.168.2.1";
    interfaceName = "eth0";
    serverPubKey = "3ADVtyHAJOyJObjbPkQv+U06I6Bma+PqxvSxV+yT7lw=";

    createKubeNode = {
        hostName,
        address,
        localAddress,
        offline ? false,
        local ? false,
    }: {

        deployment.targetHost = (if local then localAddress else address);
        # For offline machines
        deployment.hasFastConnection = offline;

        nixpkgs.localSystem.system = "aarch64-linux";
        imports = [
            ./rpi-cluster
        ];
        services.rpi-wireguard = {
            dns = {
                enable = true;
                addresses = [ masterAddress ] ++ defaultDNS;
            };
            externalInterface = interfaceName;
            internalInterfaces.wg0 = {
                privateKeyFile = "/root/wireguard-keys/private";
                address = [ (suffixAddress address) ];

                peers.gateway = {
                    allowedIPs = [ subnet ];
                    publicKey = serverPubKey;
                    endpoint = "${gatewayAddress}:51820";
                };
            };
        };

        networking.firewall.allowedTCPPorts = [
            9100 # Prometheus
        ];

        midugh.rpi-config = {
            network = {
                inherit hostName;
                enable = true;
                interface = interfaceName;
                ipv4 = {
                    defaultGateway = ipv4Gateway;
                    address = localAddress;
                    prefixLength = 24;
                };
            };
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
        derivateNode = baseConfig: extraConfig:
        lib.attrsets.recursiveUpdate (createKubeNode baseConfig) extraConfig; 
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
                deployment.targetHost = "192.168.2.5";

                # Allows deployment without internet connection
                # deployment.hasFastConnection = true;

                imports = [
                    ./rpi-cluster
                ];

                services.rpi-wireguard = {
                    enable = true;
                    isServer = true;

                    dns = {
                        enable = true;
                        addresses = defaultDNS;
                        customEntries."cluster.local" = getAddress 2;
                    };

                    externalInterface = interfaceName;
                    internalInterfaces.wg0 = {
                        address = [ "${address}/24" ];
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
                };

                midugh.rpi-config = {
                    network = {
                        inherit hostName;
                        enable = true;
                        interface = interfaceName;
                        ipv4 = {
                            defaultGateway = ipv4Gateway;
                            address = "192.168.2.5";
                            prefixLength = 24;
                        };
                    };
                    ssh.authorizedKeys = authorizedKeys;
                };
                services.rpi-kubernetes = {
                    enable = true;
                    network = {
                        inherit address;
                    };

                    kubernetesConfig.roles = ["master" "node"];
                    kubernetesConfig.api = {
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

            cluster-node-1 = derivateNode {
                localAddress = "192.168.2.47";
                address = getAddress 2;
                hostName = "cluster-node-1";
            } ({
                services.forward-proxy = {
                    enable = true;
                    hosts."*.${dnsSubnet}" = {
                        forceSsl = false;
                        proxyUrl = "http://127.0.0.1:30792";
                    };
                };
            });

            cluster-node-2 = createKubeNode {
                hostName = "cluster-node-2";
                localAddress = "192.168.2.30";
                address = (getAddress 3);
            };

            cluster-node-3 = createKubeNode {
                hostName = "cluster-node-3";
                localAddress = "192.168.2.31";
                address = (getAddress 4);
            };
        };
    };
}
