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

        dns = {
            enable = mkEnableOption "DNS in wireguard";

            interface = {
                description = "The network interface for wireguard";
                type = types.str;
                default = "wg0";
            };

            domain = mkOption {
                description = "The default domain";
                type = types.nullOr types.str;
                default = null;
            };

            addresses = mkOption {
                description = "The addresses of the dns server if client, the DNS servers to query if server";
                type = types.listOf types.str;
            };

            customEntries = mkOption {
                description = "Custom dns entries";
                example = {
                    "my-local-address" = "192.168.1.42";
                };

                default = {};
                type = types.attrsOf types.str;
            };
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
            networking.wg-quick.interfaces = forEachInterface (interface: ifcfg: 
            let natCommand = 
                let commands = builtins.map (ip: "-s ${ip}") ifcfg.address;
                in builtins.concatStringsSep " " commands;
            in {
                postUp = strings.optionalString cfg.isServer ''
                    ${pkgs.iptables}/bin/iptables -A FORWARD -i ${cfg.externalInterface} -j ACCEPT
                    ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING ${natCommand} -o ${cfg.externalInterface} -j MASQUERADE
                '';
                preDown = strings.optionalString cfg.isServer ''
                    ${pkgs.iptables}/bin/iptables -D FORWARD -i ${cfg.externalInterface} -j ACCEPT
                    ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING ${natCommand} -o ${cfg.externalInterface} -j MASQUERADE
                '';
            });

            services.dnsmasq = mkIf cfg.dns.enable {
                enable = true;
                /*extraConfig = ''
                    interface=${cfg.dns.interface}
                '';*/
                settings = {
                    cache-size = 500;
                    domain = cfg.dns.domain;
                };
                settings.server =
                let entries = builtins.attrValues (builtins.mapAttrs (name: addr: "/${name}/${addr}") cfg.dns.customEntries);
                in (cfg.dns.addresses ++ entries);
            };
        })
        (mkIf (! cfg.isServer) {
            networking.wg-quick.interfaces = forEachInterface (interface: ifcfg: {
                dns = cfg.dns.addresses;
            });
        })
        (mkIf ((! cfg.isServer) && cfg.dns.enable) {
            networking.nameservers = cfg.dns.addresses;
        })
        {
            networking.firewall.allowedUDPPorts = [
                cfg.listenPort
            ] ++ (lists.optional (cfg.isServer && cfg.dns.enable) 53);

            networking.firewall.allowedTCPPorts = lists.optional (cfg.isServer && cfg.dns.enable) 53;

            networking.wg-quick.interfaces = forEachInterface (interface: ifcfg: 
            let mapPeers = func: builtins.attrValues (builtins.mapAttrs func ifcfg.peers);
            in {
                inherit (ifcfg) address privateKeyFile;
                listenPort = cfg.listenPort;
                peers = mapPeers (name: peerCfg: {
                    inherit (peerCfg) allowedIPs publicKey endpoint;
                    persistentKeepalive = 25;
                });
            });
        }
    ]);
}
