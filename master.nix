{
    pkgs,
    config,
    modulesPath,
    ...
}@input:

let masterAddress = "192.168.1.142";
    masterHostname = "cluster-master";
    masterAPIPort = 6443;
in {
    imports = [
        (import ./node.nix {
            ipv4 = masterAddress;
            hostName = masterHostname;
            authorizedKeys = [
                "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch"
            ];
        } input)
    ];

    networking = {
        extraHosts = ''
            ${masterAddress} ${masterHostname}
        '';
        firewall = {
            allowedTCPPorts = [ 22 2379 6443 ];
            enable = false;
            trustedInterfaces = [ "end0" ];
        };
    };

    services.kubernetes = {
        roles = ["master" "node"];
        masterAddress = masterHostname;
        apiserverAddress = "https://${masterAddress}:${toString masterAPIPort}";
        easyCerts = true;
        apiserver = {
            securePort = masterAPIPort;
            advertiseAddress = masterAddress;
        };

        addons.dns.enable = true;
    };

    services.etcd = {
        listenClientUrls = ["http://${masterAddress}:2379"];
        advertiseClientUrls = ["http://${masterAddress}:2379"];
    };
}
