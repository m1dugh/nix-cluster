{ pkgs
, config
, lib
, ...
}:
with lib;
let cfg = config.services.calico-felix;
    inherit (config.midugh.k8s-cluster.nodeConfig) name worker master;
    inherit ((pkgs.callPackage ./lib.nix {}).types) calicoInitServiceType;
in {
  options.services.calico-felix = {
    enable = mkEnableOption "calico-felix agent service";
    initService = mkOption {
        description = "The config for the init service";
        type = calicoInitServiceType;
    };
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

    networking = {
        dhcpcd.denyInterfaces = ["cali*" "tunl*" "vxlan.calico"];

        firewall.allowedUDPPorts = [
            4789
        ];
        firewall.allowedTCPPorts = [
            179
            5473
        ];
    };

    environment.etc."cni/.net.d.wrapped/10-calico.conflist" = mkIf (worker && cfg.enable) {
        text = builtins.toJSON {
            name = "k8s-pod-network";
            cniVersion = "0.3.1";
            type = "calico";
            plugins = [
            {
                type = "calico";
                log_level = "info";
                log_file_path = "/var/log/calico/cni/cni.log";
                datastore_type = "kubernetes";
                mtu = 1500;
                nodename = name;
                ipam.type = "calico-ipam";
                policy.type = "k8s";
                kubernetes.kubeconfig = "/var/lib/cni/net.d/calico-kubeconfig";
            }
            {
                type = "portmap";
                capabilities.portMappings = true;
                snat = true;
            }
            {
                type = "bandwidth";
                capabilities.bandwidth = true;
            }
            ];
        };
    };


    environment.systemPackages = with pkgs; [
      calicoctl
    ];

    services.calico-felix.initService.enable = mkDefault false;

    systemd.services.calico-manifests-init-script = 
    let
        script = 
        let
            k = "${pkgs.kubectl}/bin/kubectl";
        in ''
        set -e

        mkdir -p /var/lib/calico/
        echo ${name} > /var/lib/calico/nodename
        ${k} apply --validate=false -f ${pkgs.calico-manifests}
        '';

    in {
        enable = cfg.initService.enable;
        path = with pkgs; [
            kubectl
        ];

        restartTriggers = [
            pkgs.calico-manifests
        ];

        inherit script;

        serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
        };

        after = [
            "kubelet.service"
            "containerd.service"
        ];

        environment = {
            KUBECONFIG = cfg.initService.kubeconfig;
        };

        unitConfig = {
            Description = "a script applying calico crds";
        };

        wantedBy = [
            "multi-user.target"
        ];
    };

    services.kubernetes.kubelet.cni = {
        packages = with pkgs; [
            calico-cni-plugin
            calico-ipam-cni-plugin
        ];
    };

  };
}
