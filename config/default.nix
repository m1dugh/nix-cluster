{
    hostName,
    ipAddress,
    masterAddress,
    masterAPIServerPort,
    pkgs,
    ...
}:
{
    imports = [
        ./secrets.nix
        ./hardware-configuration.nix
    ];

    users.users.root.openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch"
    ];

    services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        settings.PermitRootLogin = "yes";
        settings.KbdInteractiveAuthentication = false;
    };

    networking = {
        nftables.enable = true;
        inherit hostName;
        defaultGateway = {
            address = "192.168.1.1";
        };
        interfaces = {
            eth0 = {
                useDHCP = true;
                ipv4.addresses = [
                {
                    address = ipAddress;
                    prefixLength = 24;
                }
                ];
            };
        };
    };

    environment.systemPackages = with pkgs; [
        kubectl
        kubernetes
    ];

    services.kubernetes = 
    let
        api = "https://${masterAddress}:${toString masterAPIServerPort}";
    in {
        inherit masterAddress;
        apiserverAddress = api;
        easyCerts = true;
        addons.dns = {
            enable = true;
            coredns = {
                finalImageTag = "1.10.1";
                imageDigest = "sha256:a0ead06651cf580044aeb0a0feba63591858fb2e43ade8c9dea45a6a89ae7e5e";
                imageName = "coredns/coredns";
                sha256 = "0c4vdbklgjrzi6qc5020dvi8x3mayq4li09rrq2w0hcjdljj0yf9";
            };
        };
    };

    systemd.services.etcd = {
        environment = {
            ETCD_UNSUPPORTED_ARCH = "arm64";
        };
    };

    system.stateVersion = "24.05";
}
