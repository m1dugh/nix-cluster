{
    config,
    pkgs,
    lib,
    ...
}:
with lib;
let inherit (import ./lib.nix {
        inherit lib pkgs;
    }) internalInterfaceType;
    cfg = config.services.rpi-wireguard;
    forEachInterface = func: builtins.mapAttrs func cfg.internalInterfaces;
in {
    options.services.rpi-wireguard = {
        enable = mkEnableOption "rpi wireguard";
        externalInterface = mkOption {
            description = "The name of the external interface";
            default = "eth0";
            type = types.str;
        };

        isServer = mkOption {
            description = "Whether the node will be the server";
            default = false;
            type = types.bool;
        };

        internalInterfaces = mkOption {
            description = "The config for the internal interfaces";
            default = {};
            type = internalInterfaceType;
        };

        listenPort = mkOption {
            description = "The port to listen on";
            default = 51820;
            type = types.int;
        };
    };

    config = mkIf cfg.enable (
    let internalIfNames = builtins.attrNames cfg.internalInterfaces;
    in mkMerge [
        (mkIf cfg.isServer {
            networking.nat = {
                inherit (cfg) externalInterface;
                enable = true;
                internalInterfaces = internalIfNames;
            };
            networking.wireguard.interfaces = forEachInterface (interface: ifcfg: 
            let natCommand = 
                let commands = builtins.map (ip: "-s ${ip}") ifcfg.ips;
                in builtins.concatStringsSep " " commands;
            in {
                postSetup = strings.optionalString cfg.isServer ''
                    ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING ${natCommand} -o ${cfg.externalInterface} -j MASQUERADE;
                '';
                postShutdown = strings.optionalString cfg.isServer ''
                    ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING ${natCommand} -o ${cfg.externalInterface} -j MASQUERADE;
                '';
            });
        })
        {

            networking.firewall.allowedUDPPorts = [
                cfg.listenPort
            ];

            networking.wireguard.interfaces = forEachInterface (interface: ifcfg: 
            let mapPeers = func: builtins.attrValues (builtins.mapAttrs func ifcfg.peers);
            in {
                inherit (ifcfg) ips privateKeyFile;
                listenPort = cfg.listenPort;
                peers = mapPeers (name: peerCfg: {
                    inherit name;
                    inherit (peerCfg) allowedIPs publicKey endpoint;
                    persistentKeepalive = 25;
                });
            });
        }
    ]);
}
