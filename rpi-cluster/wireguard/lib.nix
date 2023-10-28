{
    pkgs,
    lib,
}:
with lib; rec {
    peerType = types.attrsOf (types.submodule ({name, config, ...}: {
        options = {
            enable = mkOption {
                default = true;
                description = "Whether to enable this peer";
                type = types.bool;
            };

            publicKey = mkOption {
                description = "The public key of the peer";
                type = types.str;
            };

            allowedIps = mkOption {
                description = "The list of allowed IPs for this peer";
                type = types.listOf types.str;
            };
        };
    }));

    internalInterfaceType = types.attrsOf (types.submodule ({name, config, ...}: {

        options = {
            enable = mkOption {
                description = "Whether to enable ${name} interface";
                default = true;
                type = types.bool;
            };

            ips = mkOption {
                description = "The default ips within the vpn";
                default = [];
                type = types.listOf types.str;
                example = [ "10.100.0.1/24" ];
            };

            privateKeyFile = mkOption {
                description = "The path to the private key file";
                type = types.str;
            };

            peers = mkOption {
                type = peerType;
                default = {};
            };
        };

    }));
}
