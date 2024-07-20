{ config
, lib
, ...
}:
with lib;
{
  types = rec {
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

        tls = mkEnableOption "enable tls in cluster";

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
