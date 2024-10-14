{ lib
, config
, ...
}:
with lib;
let
  extraNatConfigType = {
    options = {
      prerouting = mkOption {
        type = types.lines;
        description = "A list of prerouting rules to add to the gateway nat";
        default = "";
      };

      postrouting = mkOption {
        type = types.lines;
        description = "A list of postrouting rules to add to the gateway nat";
        default = "";
      };
    };
  };
  cfg = config.midugh.gateway;
in
{
  options.midugh.gateway = {
    enable = mkEnableOption "Gateway module";

    internalInterface = mkOption {
      type = types.str;
      description = "The internal interface";
    };

    externalInterface = mkOption {
      type = types.str;
      description = "The external interface";
    };

    port = mkOption {
      type = types.int;
      description = "The port for the wireguard server";
      default = 51820;
    };

    ipAddresses = mkOption {
      type = types.listOf types.str;
      description = "The internal ips for the server";
      default = [ ];
    };

    extraNatConfig = mkOption {
      type = types.submodule extraNatConfigType;
      default = { };
    };

    clients = mkOption {
      type = types.attrsOf types.str;
      description = "The addresses to forward";
      default = { };
      example = literalExpression ''
        {
            # 10.200.0.0/24 is vpn subnet
            # 192.168.1.0/24 is lan subnet
            "10.200.0.10" = "192.168.1.10";
            "10.200.0.10" = "192.168.1.10";
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.networking.nftables.enable;
        message = "The firewall package should be nftables";
      }
    ];

    networking = {
      nat = {
        enable = true;
        externalInterface = cfg.externalInterface;
        internalInterfaces = [ cfg.internalInterface ];
      };
      firewall.allowedUDPPorts = [ cfg.port ];

      nftables.tables.gateway-nat =
        let
          clients = attrsets.mapAttrsToList (vpnAddr: lanAddr: "ip daddr ${vpnAddr} dnat to ${lanAddr};") cfg.clients;
        in
        {
          content = ''
            chain postrouting {
                type nat hook postrouting priority 100;
                ${cfg.extraNatConfig.postrouting}
            }

            chain prerouting {
                type nat hook prerouting priority -100;
                ${strings.concatStringsSep "\n" clients}
                ${cfg.extraNatConfig.prerouting}
            }
          '';

          family = "inet";
        };

      wireguard.interfaces.${cfg.internalInterface} =
        let ips = cfg.ipAddresses ++ builtins.attrNames cfg.clients;
        in {
          inherit ips;
          listenPort = cfg.port;
        };
    };
  };
}
