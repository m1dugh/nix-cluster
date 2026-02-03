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

    pkiRootDir = lib.mkOption {
      type = lib.types.str;
      description = "Path to the PKI root directory for Kubernetes certificates";
      default = "/var/lib/kubernetes/pki/";
    };

    master = lib.mkOption {
      type = masterOptionType;
      description = "Kubernetes master node configuration";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      imports = [
        ./kubelet.nix
        ./container-runtime.nix
        ./kube-proxy.nix
      ] ++ (lib.lists.optional cfg.master.enable ([
        ./kube-apiserver.nix
        ./kube-controller-manager.nix
        ./kube-scheduler.nix
        ./etcd.nix
      ]));
    in
    {
      inherit imports;
    }
  );
}
