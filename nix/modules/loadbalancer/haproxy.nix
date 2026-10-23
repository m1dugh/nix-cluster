{ lib, config, ... }:
let
  cfg = config.services.cluster.haproxy;

  mkFrontend =
    {
      remotePort,
      localPort,
      address,
      interface,
    }:
    let
      bindAddress = if address == null then "*" else address;
    in
    ''
      frontend fe-${toString localPort}
        bind ${bindAddress}:${toString localPort}
        default_backend be-${toString localPort}

      backend be-${toString localPort}
        balance roundrobin
      ${lib.concatMapStringsSep "\n" (
        node: "    server ${node} ${node}:${toString remotePort} check"
      ) cfg.nodes}
    '';

  addressesByInterface = lib.groupBy (p: p.interface) (
    lib.filter (p: p.address != null) cfg.ports
  );
in
{
  options.services.cluster.haproxy = {
    enable = lib.mkEnableOption "cluster haproxy load balancer";

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Network interface to bind per-port publish addresses on.";
    };

    nodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Backend node addresses to load-balance across.";
      default = [ ];
    };

    ports = lib.mkOption {
      description = "List of (remotePort, localPort, address, interface) tuples to bind and forward.";
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            remotePort = lib.mkOption {
              type = lib.types.port;
              description = "Port on the backend nodes to forward to.";
            };
            localPort = lib.mkOption {
              type = lib.types.port;
              description = "Port to bind on the publish address.";
            };
            address = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Address to bind this port on. Added to `interface` (or this
                port's own `interface` override) if not already present
                there. If null, binds on all addresses.
              '';
            };

            interface = lib.mkOption {
              type = lib.types.str;
              default = cfg.interface;
              description = ''
                Network interface to bind this port's `address` on.
                Defaults to the top-level `interface`; set per-port when an
                `address` belongs to a different interface/vlan.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    networking.interfaces = lib.mapAttrs (
      interface: ports: {
        ipv4.addresses = map (addr: {
          address = addr;
          prefixLength = 32;
        }) (lib.unique (map (p: p.address) ports));
      }
    ) addressesByInterface;

    services.haproxy = {
      enable = true;
      config = ''
        global
          maxconn 4096

        defaults
          mode tcp
          timeout connect 5s
          timeout client 50s
          timeout server 50s

        ${lib.concatMapStringsSep "\n" mkFrontend cfg.ports}
      '';
    };
  };
}
