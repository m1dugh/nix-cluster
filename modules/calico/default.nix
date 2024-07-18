{
    pkgs,
    config,
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
            type = types.submodule ({...}: {
                options = {
                    endpoints = mkOption {
                        type = types.listOf types.str;
                        description = "The list of endpoints for etcd";
                        example = literalExpression ''
                        [
                            "http://localhost:2379"
                        ]
                        '';
                    };

                    caFile = mkOption {
                        type = types.nullOr types.str;
                        description = "The path to the etcd server cert, only required if using https";
                        default = null;

                        example = "./path/to/ca.crt";
                    };

                    certFile = mkOption {
                        type = types.nullOr types.str;
                        description = "The path to certificate for client auth";
                        default = null;

                        example = "./path/to/etcd.crt";
                    };

                    keyFile = mkOption {
                        type = types.nullOr types.str;
                        description = "The path to key for client auth";
                        default = null;

                        example = "./path/to/etcd.pem";
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

        systemd.services.calico = 
        let content = with cfg.etcd; ''
            FELIX_DATASTORETYPE=etcdv3
            FELIX_ETCDENDPOINTS=${strings.concatStringsSep "," endpoints}
        ''
        + strings.optionalString (caFile != null) ''
            FELIX_ETCDCAFILE=${caFile}
        ''
        + strings.optionalString (certFile != null) ''
            FELIX_ETCDCERTFILE=${certFile}
        ''
        + strings.optionalString (keyFile != null) ''
            FELIX_ETCDKEYFILE=${keyFile}
        '';
        envFile = pkgs.writeText "calico.env" content;
        in {
            unitConfig = {
                Description = "The calico cni plugin";
                After = [
                    "syslog.target"
                    "network.target"
                ];
            };

            serviceConfig = {
                User = "root";
                EnvironmentFile = envFile;
                KillMode = "process";
                Restart = "on-failure";
                LimitNOFILE = 32000;
            };

            preStart = "mkdir -p /var/run/calico";
            script = "${pkgs.calico-node} -felix";
            wantedBy = [
                "multi-user.target"
            ];
        };
    };
}
