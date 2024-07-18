{
    pkgs,
    config,
    options,
    lib,
    ...
}:
with lib;
let cfg = config.services.calico;
in {
    options.services.calico = {
        enable = mkEnableOption "calico";
        etcd = mkOption {
            description = "The config for etcd";
            type = types.submodule ({}: {
                options = {
                    endpoints = mkOption {
                        type = types.listOf types.string;
                        description = "The list of endpoints for etcd";
                        exampleLitteral = ''
                        [
                            "http://localhost:2379"
                        ]
                        '';
                    };
                };
            });
        };
    };

    config = mkIf cfg.enable {

        assertions = [
            {
                assertion = builtins.length cfg.etcd.endpoints > 0;
                message = "There should be at least one etcd endpoint";
            }
        ];

        environment.systemPackages = with pkgs; [
            calicoctl
            calico-node
        ];

        systemd.services.calico = {
            unitConfig = {
                Description = "The calico cni plugin";
                After = [
                    "syslog.target"
                    "network.target"
                ];
            };

            serviceConfig = {
                User = "root";
                Environment = ''
                    ETCD_ENDPOINTS=${cfg.etcd.endpoints}
                '';
            };

            preStart = "mkdir -p /var/run/calico";
            script = "${pkgs.calico-node} -felix";
        };
    };
}
