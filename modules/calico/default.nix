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

                    caFile = mkOption {
                        type = types.nullOr types.path;
                        description = "The path to the etcd server cert, only required if using https";
                        default = null;

                        exampleLitteral = ''
                            ./path/to/etcd.pem
                        '';
                    };

                    certFile = mkOption {
                        type = types.nullOr types.path;
                        description = "The path to certificate for client auth";
                        default = null;

                        exampleLitteral = ''
                            ./path/to/etcd.crt
                        '';
                    };

                    keyFile = mkOption {
                        type = types.nullOr types.path;
                        description = "The path to key for client auth";
                        default = null;

                        exampleLitteral = ''
                            ./path/to/etcd.pem
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

        systemd.services.calico = 
        let envFile = lib.writeText "$out/calico.env" (strings.conactStringsSep "\n" (with cfg.etcd;
        [
        ''
            FELIX_DATASTORETYPE=etcdv3
            FELIX_ETCDENDPOINTS=${strings.concatStringsSep "," endpoints}
        ''
        strings.optionalString (not isNull caFile) "FELIX_ETCDCAFILE=${caFile}"
        strings.optionalString (not isNull certFile) "FELIX_ETCDCERTFILE=${certFile}"
        strings.optionalString (not isNull keyFile) "FELIX_ETCDKEYFILE=${keyFile}"
        ]));
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
