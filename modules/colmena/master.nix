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

  mkFrontProxySecret = f: (mkSecret f) // {
    keyFile = ../../generated-certs/kubernetes/front-proxy/${f};
  };

  mkEtcdSecret = filename: rec {
    keyFile = ../../generated-certs/etcd/${filename};
    destDir = "/var/lib/kubernetes/ssl/";
    user = "kubernetes";
    group = user;
    permissions = "0400";
  };
in
{
  deployment.keys = mkIf nodeConfig.master ((attrsets.genAttrs [
    "ca.pem"
    "ca-key.pem"
    "kube-api-server.pem"
    "kube-api-server-key.pem"
    "kube-scheduler.pem"
    "kube-scheduler-key.pem"
    "service-accounts.pem"
    "service-accounts-key.pem"
    "kube-controller-manager.pem"
    "kube-controller-manager-key.pem"
  ]
    mkSecret) // {
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

    # TODO: generate proper kubeconfigs for controller manager
    "kube-controller-manager-authorization.kubeconfig" = mkSecret "admin.kubeconfig";
    "kube-controller-manager-authentication.kubeconfig" = mkSecret "admin.kubeconfig";

    "front-proxy-ca-key.pem" = mkFrontProxySecret "ca-key.pem";
    "front-proxy-ca.pem" = mkFrontProxySecret "ca.pem";
    "front-proxy-client.pem" = mkFrontProxySecret "front-proxy-client.pem";
    "front-proxy-client-key.pem" = mkFrontProxySecret "front-proxy-client-key.pem";
  });
}
