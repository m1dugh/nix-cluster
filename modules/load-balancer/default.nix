{ config
, lib
, ...
}:
let
  cfg = config.midugh.load-balancer;
  portMappingType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "The name of the port to forward";
          default = name;
          example = "https";
        };
        port = lib.mkOption {
          type = lib.types.ints.between 0 65535;
          description = "The port to bind to the address.";
          example = 443;
        };
        targetPort = lib.mkOption {
          type = lib.types.ints.between 0 65535;
          description = "The port to forward the traffic to.";
          example = 30676;
        };

        type = lib.mkOption {
          type = lib.types.enum [ "udp" "tcp" ];
          default = "tcp";
        };
      };
    }
  );
  addressType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "The name of the load balancer";
          default = name;
        };
        enable = lib.mkOption {
          default = true;
          type = lib.types.bool;
          description = "Whether to enable this address";
        };
        interface = lib.mkOption {
          type = lib.types.str;
          description = "The interface to add the address on.";
        };

        address = lib.mkOption {
          type = lib.types.str;
          description = "The address to add.";
        };

        targets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "The target addresses to proxy traffic to.";
          default = [ ];
        };

        ports = lib.mkOption {
          type = lib.types.attrsOf portMappingType;
          default = { };
          description = "The mapping of ports for the load balancer";
        };
      };
    }
  );
in
{
  options.midugh.load-balancer = {
    enable = lib.mkEnableOption "load balancer";

    addresses = lib.mkOption {
      type = lib.types.attrsOf addressType;
      default = { };
      description = "The mapping of targets";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      allTargets = builtins.filter (a: a.enable) (lib.attrsets.attrValues cfg.addresses);
      generatePorts =
        { name
        , address
        , targets
        , ports
        , ...
        }: map
          (p: p // {
            load-balancer-name = name;
            inherit address targets;
          })
          (lib.attrsets.attrValues ports);
      allPorts = lib.lists.flatten (
        map generatePorts allTargets
      );
      interfaces = lib.attrsets.catAttrs "interface" allTargets;
      getAddresses = ifname: builtins.filter ({ interface, ... }: interface == ifname) allTargets;
      perIfaceAddresses = lib.attrsets.genAttrs interfaces getAddresses;
      networkingAddresses = lib.attrsets.mapAttrs
        (name: addresses: {
          ipv4.addresses = map
            ({ address, ... }: {
              inherit address;
              prefixLength = 32;
            })
            addresses;
        })
        perIfaceAddresses;
    in
    {
      networking.interfaces = networkingAddresses;
      services.haproxy = lib.mkIf ((builtins.length allPorts) > 0) {
        enable = true;
        config =
          let
            genPortConfig =
              { load-balancer-name
              , address
              , name
              , targets
              , port
              , targetPort
              , ...
              }:
              let
                front-name = "${load-balancer-name}-${name}";
                back-name = "back-${front-name}";
                targetsStr = lib.lists.imap0 (i: v: "  server server-${toString i} ${v}:${toString targetPort} check") targets;
              in
              ''
                frontend ${front-name}
                  mode tcp
                  bind ${address}:${toString port}
                  default_backend ${back-name}
                backend ${back-name}
                  mode tcp
                  balance roundrobin
                ${lib.strings.concatStringsSep "\n" targetsStr}
              '';
          in
          lib.strings.concatStringsSep "\n" (map genPortConfig allPorts);
      };
    }
  );
}
