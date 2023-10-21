{
    ipv4,
    hostName,
    authorizedKeys ? [],
    masterAddress ? null,
    masterHostname ? "cluster-master",
    extraPorts ? [],
    systemVersion ? "23.11",
    kubernetesRoles ? [ "node" ],
    apiPort ? 6443,
    enableDns ? true,
}:
{
    pkgs,
    lib,
    config,
    ...
}:
{

    nixpkgs.localSystem.system = "aarch64-linux";

    imports = [
        <nixpkgs/nixos/modules/installer/sd-card/sd-image.nix>
    ];
    
    # Avoids kubernetes error with swap
    swapDevices = lib.mkForce [];

    # Default config for sd based image for RPi
    sdImage = {
        populateFirmwareCommands = 
        let configTxt = pkgs.writeText "config.txt" ''
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

    system.stateVersion = systemVersion;
    services.openssh = {
        enable = true;
    };

    users.users.root = {
        hashedPassword = "$6$QuhEKr0ZX46NJqjv$s.euYXMmAmDmqP65EuTO7vYURZTH/wbdkZQ/TcuUvGD4SGM4z7SOn2V1YGop87OJ.Lg.3UJndI5hSBdlTzAzI.";
        openssh.authorizedKeys.keys = authorizedKeys;
    };

    networking = {
        extraHosts = lib.concatMapStrings ({ addr, name }: "${addr} ${name}\n")
        ([
        {
            addr = ipv4;
            name = hostName;
        }
        ] ++ (if masterAddress != null then [{
            addr = masterAddress;
            name = masterHostname;
        }] else []));
        firewall = {
            enable = false;
            allowedTCPPorts = [ 22 ] ++ extraPorts;
        };
        hostName = hostName;
  };

    boot.kernelParams = [
        "console=ttyS0,115200n8"
        "console=ttyAMA0,115200n8"
        "console=tty0"
        "cgroup_memory=1"
        "cgroup_enable=memory"
    ];

    # Sets kernel to latest packages
    boot.kernelPackages = pkgs.linuxPackages_latest;
    # Adds verbose logs
    boot.consoleLogLevel = lib.mkDefault 7;

    boot.loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
    };

    # Adds driver for raspi 4 components
    boot.initrd.availableKernelModules = [
        "vc4"
        "bcm2835_dma"
        "i2c_bcm2835"
        "sun4i_drm"
        "sun8i_drm_hdmi"
        "sun8i_mixer"
    ];

    # Required kubernetes packages
    environment.systemPackages = with pkgs; [
        kompose
        kubectl
        kubernetes

        cfssl
        openssl

        vim
    ];

    # ETCD fix on ARM devices.
    services.etcd.extraConf.UNSUPPORTED_ARCH = "arm64";

    services.kubernetes = 
    let apiAddress = (if masterAddress != null then masterAddress else ipv4 );
    api = "https://${apiAddress}:${toString apiPort}";
    isMaster = builtins.any (role: role == "master") kubernetesRoles;
    isNode = builtins.any (role: role == "node") kubernetesRoles;
    in {
        masterAddress = apiAddress;
        roles = kubernetesRoles;

        apiserverAddress = api;
        apiserver = lib.mkIf isMaster {
            securePort = apiPort;
            advertiseAddress = apiAddress;
        };

        kubelet.kubeconfig.server = lib.mkIf isNode api;

        easyCerts = true;

        pki = {
            cfsslAPIExtraSANs = (builtins.filter (v: v != null) [ masterHostname masterAddress ipv4 ]);
        };

        addons.dns = {
            enable = enableDns;
            coredns = {
                finalImageTag = "1.10.1";
                imageDigest = "sha256:a0ead06651cf580044aeb0a0feba63591858fb2e43ade8c9dea45a6a89ae7e5e";
                imageName = "coredns/coredns";
                sha256 = "0c4vdbklgjrzi6qc5020dvi8x3mayq4li09rrq2w0hcjdljj0yf9";
            };
        };
    };
}
