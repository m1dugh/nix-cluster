{ nodeConfig
, lib
, ...
}:
with lib;
let
    mkSecret = filename: rec {
        keyFile = ../../generated-certs/kubernetes/${filename};
        destDir = "/var/lib/kubernetes/ssl/";
        user = "kubernetes";
        group = user;
        permissions = "0400";
    };

    mkEtcdSecret = filename: rec {
        keyFile = ../../generated-certs/etcd/${filename};
        destDir = "/var/lib/kubernetes/ssl/";
        user = "kubernetes";
        group = user;
        permissions = "0400";
    };
in {
    deployment.keys = mkIf nodeConfig.master ((attrsets.genAttrs [
        "ca.pem"
        "ca-key.pem"
        "kube-api-server.pem"
        "kube-api-server-key.pem"
        "kube-scheduler.pem"
        "kube-scheduler-key.pem"
        "service-accounts.pem"
        "service-accounts-key.pem"
    ] mkSecret) // {
        "etcd-k8s-ca.pem" = mkEtcdSecret "ca.pem" // {
            name = "etcd-ca.pem";
        };
        "etcd-client.pem" = mkEtcdSecret "client.pem";
        "etcd-client-key.pem" = mkEtcdSecret "client-key.pem";
        "config" = {
            destDir = "/root/.kube";
            user = "root";
            group = "root";
            keyFile = ../../generated-certs/kubernetes/admin.kubeconfig;
        };
    });
}
