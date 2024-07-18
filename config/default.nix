{
    config,
    masterAddress,
    ipAddress,
    ...
}:
let secrets = config.sops.secrets;
in {
    users.users.root.password = "toor";

    networking = {
        hostName = "cluster-master";
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

    midugh.k8s-cluster = {
        enable = true;
        master = true;
        worker = true;
        kubeMasterAddress = masterAddress;
    };

    system.stateVersion = "24.05";
}
