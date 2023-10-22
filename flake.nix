{
    description = "A very basic flake";

    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    outputs = {
        nixpkgs,
        ...
    }:
let authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQClvwb6jBskbU/RfINu34+kDA8+FeyFQ6xoQgd0EBGXpJfiYiXlYU3B9Wmfu88YP4UqQka+WgQ/bncY8Ro22TPGi1qoFCp5W7zlmuBc1B462qFgtOF8k9SyHBzg4t1td4VS/PYp4h+K5xdQ+Vj3ZP+wdwlRxD+uABnjEgU34OuEn53foLLPGgEVrOehv0xU/DcBtdj1x/zCn9JnVExNGy2K5WTlOAmHDFCUzFU3BuDAa21HMFgbkCjDMmReUoQvyW1YqmjACjHJukV1v7l40GcFHNf4I/ggDFlABmxL8MCQoTxBfDTf1yPI9BJ6uPzu0Kp36JnC27NfF5UQw9rnYa5OHv+s3TW3QrRP52GshGU7EQjVke2/tGUDy74Rr1vtWIsFTTQ93Nx79rS/Jf1ad2dPCd0U2wAveYix7CxngfOKuWmPcNTEP6YOx+FmVA2/Gk/ipSBqRuquKVgfMhayfTBLNVCJpkog6rH1qXOK6f6ytiK8yrz1HV4KHl/yF/MiF9s= midugh@midugh-arch" ];
    masterAddress = "192.168.2.5";
    in {
        nixopsConfigurations.default = {
            inherit nixpkgs;
            network = {
                storage.legacy = {
                    databasefile = "~/.nixops/deployments.nixops";
                };
                description = "cluster";
            };
            cluster-master =
                let address = masterAddress;
            hostname = "cluster-master";
            in {
                nixpkgs.localSystem.system = "aarch64-linux";
                deployment.targetHost = address;
                imports = [
                    ./rpi-cluster
                ];
                services.rpi-cluster = {
                    enable = true;
                    network = {
                        inherit address authorizedKeys hostname;
                        extraPorts = [ 2049 ];
                    };

                    kubernetesConfig.roles = ["master" "node"];
                    kubernetesConfig.api.port = 6443;

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
                        /nfs 192.168.2.0/24(insecure,rw,sync,no_subtree_check,fsid=0)
                    '';
                };

            };
            cluster-node-1 = 
                let address = "192.168.2.15";
            hostname = "cluster-node-1";
            in {
                nixpkgs.localSystem.system = "aarch64-linux";
                imports = [
                    ./rpi-cluster
                ];
                deployment.targetHost = address;
                services.rpi-cluster = {
                    enable = true;
                    network = {
                        inherit address hostname authorizedKeys;
                    };

                    kubernetesConfig.api = {
                        inherit masterAddress;
                    };

                    dns.enable = true;
                };
            };
        };
    };
}
