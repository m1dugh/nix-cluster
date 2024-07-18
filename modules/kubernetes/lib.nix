{
    lib,
    ...
}:
with lib;
{
    types = {
        etcdHostType = types.submodule ({
            options = {
                name = mkOption {
                    type = types.str;
                    default = config.networking.fqdnOrHostName;
                    description = "The name of the host";
                };

                address = mkOption {
                    type = types.str;
                    default = config.networking.fqdnOrHostName;
                    description = "The address of the host";
                };

                port = mkOption {
                    type = types.int;
                    default = 2379;
                    description = "The port for the etcd service";
                };

                peerPort = mkOption {
                    type = types.int;
                    default = 2380;
                    description = "The port for peer communication";
                };
            };
        });
    };
}
