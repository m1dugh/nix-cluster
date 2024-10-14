{ nodeConfig
, lib
, ...
}:
with lib;
let
  mkSecret = filename: rec {
    keyFile = ../../generated-certs/etcd/${filename};
    destDir = "/var/lib/flannel/ssl/";
    user = "root";
    group = user;
    permissions = "0400";
  };
  inherit (nodeConfig) master worker;
  k8sNode = master || worker;
in {
    deployment.keys = mkIf k8sNode {
        "flannel-etcd-ca.pem" = (mkSecret "ca.pem") // {
            name = "etcd-ca.pem";
        };
        "flannel-etcd-client-key.pem" = (mkSecret "client-key.pem") // {
            name = "etcd-client-key.pem";
        };
        "flannel-etcd-client.pem" = (mkSecret "client.pem") // {
            name = "etcd-client.pem";
        };
    };
}
