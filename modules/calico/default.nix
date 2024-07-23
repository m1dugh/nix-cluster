{ pkgs
, config
, lib
, ...
}:
with lib;
let cfg = config.services.calico-felix;
in {
  options.services.calico-felix = {
    enable = mkEnableOption "calico-felix agent service";
    etcd = mkOption {
      description = "The config for etcd";
      type = types.submodule ({ ... }: {
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
            type = types.nullOr types.path;
            description = "The path to the etcd server cert, only required if using https";
            default = null;

            example = literalExpression "./path/to/ca.crt";
          };

          certFile = mkOption {
            type = types.nullOr types.path;
            description = "The path to certificate for client auth";
            default = null;

            example = literalExpression "./path/to/etcd.crt";
          };

          keyFile = mkOption {
            type = types.nullOr types.path;
            description = "The path to key for client auth";
            default = null;

            example = literalExpression "./path/to/etcd.pem";
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
    ];

    systemd.services.calico-felix =
      let
        content = with cfg.etcd; ''
          NIX_LD=${pkgs.nix-ld}/lib/ld.so
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
      in
      {
        path = with pkgs; [
            calico-node
            nix-ld
        ];
        unitConfig = {
          Description = "Calico Felix agent";
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
        script = "${pkgs.calico-node}/bin/calico-node -felix";
        wantedBy = [
          "multi-user.target"
        ];
      };
  };
}
