{ lib
, config
, ...
}:
let
  cfg = config.midugh.kubernetes;
  masterOptionType = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "Kubernetes master components";
      schedulable = lib.mkOption {
        type = lib.types.bool;
        description = "Whether the master node is schedulable for workloads";
        default = false;
      };
    };
  };
in
{
  options.midugh.kubernetes = {
    enable = lib.mkEnableOption "Kubernetes module";
    nodeName = lib.mkOption {
      type = lib.types.str;
      description = "The name of the node";
    };

    pkiRootDir = lib.mkOption {
      type = lib.types.str;
      description = "Path to the PKI root directory for Kubernetes certificates";
      default = "/var/lib/kubernetes/pki/";
    };

    pkiLocalDir = lib.mkOption {
      type = lib.types.str;
      description = "Path to the local pki folder";
    };

    master = lib.mkOption {
      type = masterOptionType;
      description = "Kubernetes master node configuration";
      default = { };
    };
  };

    imports = [
        ./kubelet.nix
        ./container-runtime.nix
        ./kube-proxy.nix
        ./kube-apiserver.nix
        ./kube-controller-manager.nix
        ./kube-scheduler.nix
        ./etcd.nix
    ];

    config.services.kubernetes = lib.mkIf cfg.enable {
        easyCerts = false;
    };
}
