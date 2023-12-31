{
    description = "A very basic flake";

    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";

    outputs = {
        nixpkgs,
        ...
    }:
let authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch" ];
    defaultDNS = [ "192.168.1.1" ];
    gatewayAddress = "192.168.2.145";
    dnsSubnet = "local.midugh.fr";
    getAddress = n: 
        let subnetPrefix = "10.200.0";
        in "${subnetPrefix}.${builtins.toString n}";
    suffixAddress = addr: "${addr}/32";
    masterAddress = getAddress 100;
    subnet = getAddress 0 + "/24";
    vpnGateway = getAddress 1;
    ipv4Gateway = "192.168.1.1";
    localPrefixLen = 22;
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
                addresses = [ vpnGateway ] ++ defaultDNS;
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
                    prefixLength = localPrefixLen;
                };
            };
            ssh.authorizedKeys = authorizedKeys;
        };
        services.rpi-kubernetes = {
            enable = true;
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
                localAddress = "192.168.2.142";
                hostName = "cluster-master";
                local = false;
            in {
                nixpkgs.localSystem.system = "aarch64-linux";
                deployment.targetHost = if local then localAddress else address;

                # Allows deployment without internet connection
                deployment.hasFastConnection = false;

                imports = [
                    ./rpi-cluster
                ];

                services.rpi-wireguard = {
                    enable = true;
                    dns = {
                        enable = true;
                        addresses = [ gatewayAddress ] ++ defaultDNS;
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
                    2049 # nfs server
                    9100 # prometheus
                    80   # http port
                    443  # https port
                ];

                midugh.rpi-config = {
                    network = {
                        inherit hostName;
                        enable = true;
                        interface = interfaceName;
                        ipv4 = {
                            defaultGateway = ipv4Gateway;
                            address = localAddress;
                            prefixLength = localPrefixLen;
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

                services.nfs.server = {
                    enable = true;
                    exports =
                    let folders = [
                        "promdata"
                        "grafana"
                        "postgres"
                        "vaultwarden"
                    ];
                        rootEntry = "/nfs ${subnet}(rw,no_subtree_check,fsid=0)";
                        subfileEntries = builtins.map (sub: "/nfs/${sub} ${subnet}(rw,nohide,insecure,no_subtree_check)") folders;
                    in
                        lib.strings.concatStringsSep "\n" ([rootEntry] ++ subfileEntries);

                    extraNfsdConfig = ''
                    vers3=no
                    '';
                };

                fileSystems."/nfs" = {
                    label = "KUBE";
                    fsType = "btrfs";
                    options = [
                        "nofail"
                    ];
                };

                services.rpcbind.enable = lib.mkForce false;
            };

            cluster-node-1 = createKubeNode {
                localAddress = "192.168.2.143";
                address = getAddress 101;
                hostName = "cluster-node-1";
            };

            cluster-node-2 = createKubeNode {
                hostName = "cluster-node-2";
                localAddress = "192.168.2.144";
                address = (getAddress 102);
            };

            gateway = 
            let localAddress = gatewayAddress;
                address = (getAddress 1);
                hostName = "cluster-gateway";
                local = false;
            in {
                nixpkgs.localSystem.system = "aarch64-linux";
                deployment.targetHost = if local then localAddress else address;

                imports = [
                    ./rpi-cluster
                ];

                services.rpi-kubernetes.enable = false;
                services.forward-proxy.enable = false;

                midugh.rpi-config = {
                    network = {
                        inherit hostName;
                        useDHCP = true;
                        enable = true;
                        interface = interfaceName;
                    };
                    ssh.authorizedKeys = authorizedKeys ++ [
                        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDoYcw1zngwE35iEAUdwCGTae1sm8mWQ5ejsAQaCGZCY6rDBJfQKVTU2iV1WJn6SzUYHkp5z2HnSneQG/9j8g5Hio3JvijIjQeJOjk2wwVaK9Ri6bf2EWTIZPDDGM84i+kydwbTpXFTAsbfj2uHhXq/NG78Y16ReiCAcv30pRZ/8+/dN7iL0e5cmn7p+HWZY1PD/7nn82rIp6y/Vahit3amHQnu6HkyHBtHEnS0OLmH1QceFoJprvDXux1S6CWRfH8iLggBCr93cZD6eupLwqGQPZ36LSglj0rwDL6r4DBA0g0USgrQPoDrYRRBVdD79Ygt8QilpzmX9o8Jtw0BvXISI8xhzHnsrNV9GYXfn60Y7E9YZnTswsS5YB3MrmmAnCeBuPoe1r2Zuo9QFDWnT/RFMFlAIiO/hcs4KSHJyCsq0BW7LqQbLpiPw/sgp7flsvOO3U63SA+sk60TGfZU1oBSR5FLi+Wv1gfbsXzp1e4qovPfXDA043GdLkdiY1G21XY5vcWHwEpKsEzD2bgtRIDAqVCJHULji8Q9iNWEePfR2B59IE/LJJDDzHBExeUA0BHYR6+he+YPVxIQHzmXOhDp/mSftj6KQ24l3gO8IDo23PRD0xG7G/xPBTUuwNUups3mtBhp6AGp0G3/CBCAb9WE3KDUqTd5o90+FIU4i6OneQ=="
                    ];

                    ssh.authorizedIPs = [
                        "192.168.1.0/22"
                        subnet
                    ];
                };

                services.rpi-wireguard = {
                    enable = true;
                    isServer = true;

                    dns = {
                        enable = true;
                        addresses = defaultDNS;
                        customEntries.${dnsSubnet} = getAddress 100;
                    };

                    externalInterface = interfaceName;
                    internalInterfaces.wg0 = {
                        address = [ "${address}/24" ];
                        privateKeyFile = "/root/wireguard-keys/private";

                        peers.cluster-master = {
                            publicKey = "rT10J2VrIGqY/+UBc93EdE1WM3Qe3GPSwMLB0t7Y1lc=";
                            allowedIPs = [ (suffixAddress (getAddress 100)) ];
                        };

                        peers.cluster-node-1 = {
                            publicKey = "RYs58WNculdnChOdycKMZ5V2PJtc4nkfcC+ZOigDxG0=";
                            allowedIPs = [ (suffixAddress (getAddress 101)) ];
                        };

                        peers.cluster-node-2 = {
                            publicKey = "FidZaNzQqmP9OxdhdtYYi8gD2ucwijNIrPXrmqXLNR4=";
                            allowedIPs = [ (suffixAddress (getAddress 102)) ];
                        };

                        peers.midugh-pc = {
                            publicKey = "5YtnXbwCv8i0Vy2WPo1DgM4fYgXib25tnRKVHPRz7m0=";
                            allowedIPs = [ (suffixAddress (getAddress 42)) ];
                        };

                        peers.midugh-phone = {
                            publicKey = "Hpb87xmb9sTOjT4t/13BITP6l6NzQdAjOaL9f1LABk8=";
                            allowedIPs = [ (suffixAddress (getAddress 43)) ];
                        };
                    };
                };
            };
        };
    };
}
