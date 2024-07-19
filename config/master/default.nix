{
    config,
    masterAddress,
    hostName,
    masterAPIServerPort,
    lib,
    pkgs,
    ...
}:
with lib;
let secrets = config.sops.secrets;
in {
    imports = [
        ./secrets.nix
    ];

    networking.extraHosts = ''
        ${masterAddress}    ${hostName}
    '';

    midugh.gateway = {
        enable = true;
        internalInterface = "wg0";
        externalInterface = "eth0";
        ipAddresses = lists.singleton "10.200.0.1/24";
        clients = {
            "10.200.0.2" = "192.168.1.146";
            "10.200.0.3" = "192.168.1.147";
            "10.200.0.4" = "192.168.1.148";
        };
    };

    environment.systemPackages = with pkgs; [
        kubectl
        kubernetes
    ];

    services.kubernetes = {
        roles = ["master" "node"];
        apiserver = {
            securePort = masterAPIServerPort;
            advertiseAddress = masterAddress;
        };
    };

    networking.firewall.allowedTCPPorts = [ 8888 ];

    networking.wireguard.interfaces."wg0" = {
        privateKeyFile = secrets."gateway/wg0.key".path;

        peers = [
            {
                # Midugh pc
                publicKey = "5YtnXbwCv8i0Vy2WPo1DgM4fYgXib25tnRKVHPRz7m0=";
                allowedIPs = [
                    "10.200.0.100/32"
                ];
            }
            {
                # Midugh phone
                publicKey = "Hpb87xmb9sTOjT4t/13BITP6l6NzQdAjOaL9f1LABk8=";
                allowedIPs = [
                    "10.200.0.101/32"
                ];
            }
        ];
    };
}
