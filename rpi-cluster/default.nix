{
    config,
    options,
    pkgs,
    lib,
    ...
}:
with lib;
let calculateDefaultGateway = address: netmask: 
    let addrParts = strings.splitString "." address;
    gatewayParts = (lists.sublist 0 3 addrParts) ++ lists.singleton "1";
    in strings.concatStringsSep "." gatewayParts;

    inherit (import ./lib.nix {
        inherit pkgs lib;
    }) hostType;
    ismaster = elem "master" cfg.kubernetesConfig.roles;
    isnode = elem "node" cfg.kubernetesConfig.roles;
    cfg = config.services.rpi-cluster;
    opts = options.services.rpi-cluster;
    mkNetworkSettings = {
        address = mkOption {
            description = "ipv4 address of node";
            type = types.str;
        };

        gateway = mkOption {
            description = "ipv4 of network gateway";
            type = types.str;
            default = (calculateDefaultGateway cfg.network.address cfg.network.netmask);
        };

        netmask = mkOption {
            description = "The net mask of the network";
            type = types.str;
            default = "255.255.255.0";
        };

        hostname = mkOption {
            description = "hostname of the node";
            type = types.nullOr types.str;
            default = null;
        };

        extraPorts = mkOption {
            description = "Additional ports to open on the firewall";
            type = types.listOf types.int;

            default = [];
        };

        enableFirewall = mkOption {
            description = "Whether to enable the firewall";
            default = true;
            type = types.bool;
        };

        authorizedKeys = mkOption {
            description = "Additional ssh keys to add to root user";
            default = [];
            type = types.listOf types.str;
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

    mkForwardConfig = {
        enable = mkEnableOption "service forwarding";

        hosts = mkOption {
            type = hostType;
            default = {};
        };
    };
    forEachHost = func: builtins.mapAttrs func cfg.forward-proxy.hosts;
in {
    imports = [
        <nixpkgs/nixos/modules/installer/sd-card/sd-image.nix>
    ];
    options.services.rpi-cluster = {
        enable = mkEnableOption "rpi-cluster";
        network = mkNetworkSettings;
        kubernetesConfig = mkKubernetesConfig;
        dns = mkDnsConfig;
        etcd = mkEtcdConfig;
        forward-proxy = mkForwardConfig;
    };
    config = mkMerge ([
        (mkIf cfg.forward-proxy.enable {
            services.nginx = {
                recommendedProxySettings = true;
                enable = true;

                virtualHosts = forEachHost (host: hostConfig: {
                    forceSSL = hostConfig.forceSsl;
                    locations."/" = {
                        proxyPass = hostConfig.proxyUrl;
                    };
                });
            };
        })
        {
            sdImage = {
                populateFirmwareCommands = let configTxt = pkgs.writeText "config.txt" ''
                    [pi3]
                    kernel=u-boot-rpi3.bin
                    [pi4]
                    kernel=u-boot-rpi4.bin
                    enable_gic=1
                    armstub=armstub8-gic.bin
                    # Otherwise the resolution will be weird in most cases, compared to
                    # what the pi3 firmware does by default.
                    disable_overscan=1
                    [all]
                    # Boot in 64-bit mode.
                    arm_64bit=1
                    # U-Boot needs this to work, regardless of whether UART is actually used or not.
                    # Look in arch/arm/mach-bcm283x/Kconfig in the U-Boot tree to see if this is still
                    # a requirement in the future.
                    enable_uart=1
                    # Prevent the firmware from smashing the framebuffer setup done by the mainline kernel
                    # when attempting to show low-voltage or overtemperature warnings.
                    avoid_warnings=1
                '';
                in ''
                    (cd ${pkgs.raspberrypifw}/share/raspberrypi/boot && cp bootcode.bin fixup*.dat start*.elf $NIX_BUILD_TOP/firmware/)
                    # Add the config
                    cp ${configTxt} firmware/config.txt
                    # Add pi3 specific files
                    cp ${pkgs.ubootRaspberryPi3_64bit}/u-boot.bin firmware/u-boot-rpi3.bin
                    # Add pi4 specific files
                    cp ${pkgs.ubootRaspberryPi4_64bit}/u-boot.bin firmware/u-boot-rpi4.bin
                    cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin firmware/armstub8-gic.bin
                    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb firmware/
                '';
                populateRootCommands = ''
                    mkdir -p ./files/boot
                    ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
                '';
            };
        }
        {
            system.stateVersion = "23.11";
            services.openssh.enable = true;

            users.users.root = {
                hashedPassword = "$6$QuhEKr0ZX46NJqjv$s.euYXMmAmDmqP65EuTO7vYURZTH/wbdkZQ/TcuUvGD4SGM4z7SOn2V1YGop87OJ.Lg.3UJndI5hSBdlTzAzI.";

                openssh.authorizedKeys.keys = cfg.network.authorizedKeys;
            };

            boot.kernelParams = [
                "console=ttyS0,115200n8"
                "console=ttyAMA0,115200n8"
                "console=tty0"
                "cgroup_memory=1"
                "cgroup_enable=memory"
                "ip=${cfg.network.address}::${cfg.network.gateway}:${cfg.network.netmask}:${cfg.network.hostname}:eth0:off"
            ];
# Sets kernel to latest packages
            boot.kernelPackages = pkgs.linuxPackages_latest;
# Adds verbose logs
            boot.consoleLogLevel = lib.mkDefault 7;

            boot.loader = {
                grub.enable = false;
                generic-extlinux-compatible.enable = true;
            };

            boot.initrd = {
                kernelModules = [ "nfs" ];
                supportedFilesystems = [ "nfs" ];

                # Adds driver for raspi 4 components
                availableKernelModules = [
                    "vc4"
                    "bcm2835_dma"
                    "i2c_bcm2835"
                    "sun4i_drm"
                    "sun8i_drm_hdmi"
                    "sun8i_mixer"
                ];
            };


# Required kubernetes packages
            environment.systemPackages = with pkgs; [
                kompose
                kubectl
                kubernetes

                cfssl
                openssl

                vim

                nfs-utils
            ];

        }
        (mkIf cfg.enable {
            networking.nftables.enable = true;
            networking.firewall = {
                enable = cfg.network.enableFirewall;
                allowedTCPPorts =
                cfg.network.extraPorts ++
                (if ismaster then [
                    cfg.etcd.port
                    cfg.kubernetesConfig.api.port
                    8888 # flannel port
                    10259 # kube scheduler
                    10257 # kube-controller-manager
                    10250 # kubelet api
                ] else []) ++
                (if isnode then [
                    10250 # kubelet api
                ] else []) ++
                (lists.optionals cfg.forward-proxy.enable [
                    80
                    443
                ]);
            };

# ETCD fix on ARM devices.
            services.etcd.extraConf.UNSUPPORTED_ARCH = "arm64";
            networking.hostName = cfg.network.hostname;

            networking.extraHosts =
            let buildHosts = lib.concatMapStrings ({ address, hostname }: "${address} ${hostname}\n");
            in buildHosts ([ { inherit (cfg.network) address hostname; } ]);

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
        })
        (mkIf (cfg.enable && ismaster) {
            services.kubernetes.apiserver = 
            let inherit (cfg.kubernetesConfig) api;
            in {
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

        (mkIf (cfg.enable && (isnode)) {
            services.kubernetes.kubelet.kubeconfig.server = apiUrl;
        })
    ]);
}
