{ lib
, config
, ...
}:
with lib;
let
  portForwardType = {
    options = {
      sourcePort = mkOption {
        type = types.int;
        description = "The source port";
        example = 8080;
      };

      protocol = mkOption {
        type = types.enum [
          "tcp"
          "udp"
        ];
        description = "The protocol to forward";
        default = "tcp";
      };

      daddr = mkOption {
        type = types.nullOr types.str;
        description = "The original destination address";
        default = null;
        example = "192.168.1.1";
      };

      destination = mkOption {
        type = types.str;
        description = "The natted destination";
        example = "192.168.1.2:8080";
      };

      sourceInterface = mkOption {
        type = types.nullOr types.str;
        description = "The source interface";
        example = "wg0";
        default = null;
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

    portForward = mkOption {
      type = types.listOf (types.submodule portForwardType);
      default = [ ];
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

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = mkOverride 99 true;
      "net.ipv4.conf.default.forwarding" = mkOverride 99 true;
    };

    networking.nftables.tables.gateway-nat = {
      family = "ip";
      content =
        let
          lines = strings.concatMapStringsSep "\n"
            (f:
              strings.concatStrings ([
                (strings.optionalString (f.sourceInterface != null) "iifname ${f.sourceInterface} ")
                (strings.optionalString (f.daddr != null) "ip daddr ${f.daddr} ")
                "${f.protocol} dport ${toString f.sourcePort} "
                "dnat to ${f.destination};"
              ])
            )
            cfg.portForward;
        in
        ''
          chain pre {
              type nat hook prerouting priority dstnat; policy accept;
              ${lines}
          }

          chain post {
              type nat hook postrouting priority srcnat; policy accept;
              oifname "${cfg.externalInterface}" masquerade comment "from internal interfaces"
          }

          chain out {
              type nat hook output priority mangle; policy accept;
          }
        '';
    };

    networking = {
      firewall.allowedUDPPorts = [ cfg.port ];

      wireguard.interfaces.${cfg.internalInterface} =
        let ips = cfg.ipAddresses ++ builtins.attrNames cfg.clients;
        in {
          inherit ips;
          listenPort = cfg.port;
        };
    };
  };
}
