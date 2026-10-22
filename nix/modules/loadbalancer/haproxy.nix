{ lib, config, ... }:
let
  cfg = config.services.cluster.haproxy;

  mkFrontend =
    {
      remotePort,
      localPort,
      address,
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

  portAddresses = lib.unique (lib.filter (addr: addr != null) (map (p: p.address) cfg.ports));
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
      description = "List of (remotePort, localPort, address) tuples to bind and forward.";
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
                Address to bind this port on. Added to `interface` if not
                already present there. If null, binds on all addresses.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    networking.interfaces.${cfg.interface}.ipv4.addresses = map (addr: {
      address = addr;
      prefixLength = 32;
    }) portAddresses;

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
