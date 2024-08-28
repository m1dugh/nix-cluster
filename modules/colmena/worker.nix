{ nodeConfig
, lib
, ...
}:
with lib;
let
    inherit (nodeConfig) name;
    mkSecret = filename: {
        keyFile = ../../generated-certs/kubernetes/${filename};
        destDir = "/var/lib/kubernetes/ssl/";
        user = "kubernetes";
        group = "kubernetes";
        permissions = "0400";
    };
in {
    deployment.keys = mkIf nodeConfig.worker ((attrsets.genAttrs [
        "ca.pem"
        "kube-controller-manager.pem"
        "kube-controller-manager-key.pem"
        "kube-proxy.pem"
        "kube-proxy-key.pem"
    ] mkSecret) // {
        "kubelet.pem" = mkSecret "${name}.pem";
        "kubelet-key.pem" = mkSecret "${name}-key.pem";
        "calico-kubeconfig" = {
            keyFile = ../../generated-certs/kubernetes/calico.kubeconfig;
            destDir = "/var/lib/cni/net.d/";
        };
    });
}
