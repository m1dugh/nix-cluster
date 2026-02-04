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

        addons.dns = {
            enable = true;
            coredns = {
                # finalImageTag = "1.14.1";
                # imageName = "coredns/coredns";
                # imageDigest = "sha256:82b57287b29beb757c740dbbe68f2d4723da94715b563fffad5c13438b71b14a";
                # sha256 = "9dc1d202725a6ea7bc796472be8a36f614548bd2ac68d56392552e5400b2b163";
                finalImageTag = "1.10.1";
                imageDigest = "sha256:a0ead06651cf580044aeb0a0feba63591858fb2e43ade8c9dea45a6a89ae7e5e";
                imageName = "coredns/coredns";
                sha256 = "0c4vdbklgjrzi6qc5020dvi8x3mayq4li09rrq2w0hcjdljj0yf9";
            };
        };
    };
}
