{ lib
, ...
}:
with lib;
let
    mkEnableTrueOption = msg: mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable ${msg}";
    };
in {
    mkEtcdEndpoint = {
        address,
        etcd,
        ...
    }:
    let
        inherit (etcd) tls port;
        scheme = if tls then "https" else "http";
    in "${scheme}://${address}:${toString port}";
  types = rec {
    apiserverConfigType = types.submodule({
        options = {
            address = mkOption {
                type = types.str;
                description = "The address of the service";
            };

            port = mkOption {
                type = types.int;
                description = "The port for the service";
            };

            serviceClusterIpRange = mkOption {
                type = types.str;
                default = "10.32.0.0/24";

            };
        };
    });

    nodeConfigType = types.submodule ({
      options = {
        name = mkOption {
          type = types.str;
          description = "The name of the node";
        };

        address = mkOption {
            type = types.str;
            description = "The IP address of the node";
        };

        etcd = mkOption {
            type = etcdHostType;
            description = "The config for the etcd cluster node";
            default = {};
        };

        master = mkEnableOption "use this node as control-plane";
        worker = mkEnableOption "use this node as worker";
      };
    });
    etcdHostType = types.submodule ({
      options = {
        enable = mkEnableOption "use this node in etcd cluster";
        address = mkOption {
          type = types.nullOr types.str;
          description = "The address to bind etcd to";
          default = null;
        };

        openFirewall = mkOption {
            type = types.bool;
            description = "Whether to open firewall for etcd";
            default = false;
        };

        tls = mkEnableTrueOption "tls for this node";

        port = mkOption {
          type = types.int;
          default = 2379;
          description = "The port for the etcd service";
        };

        peerPort = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "The port for peer communication";
        };
      };
    });
  };
}
