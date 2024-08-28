{ nodeConfig
, lib
, ...
}:
with lib;
let
    inherit (nodeConfig) name;
    mkSecret = filename: {
        keyFile = ../../generated-certs/etcd/${filename};
        destDir = "/var/lib/etcd/ssl/";
        user = "etcd";
        group = "etcd";
        permissions = "0400";
    };
in {
    deployment.keys = mkIf nodeConfig.etcd.enable {
        "etcd-ca.pem" = mkSecret "ca.pem" // {
            name = "ca.pem";
        };
        "etcd.pem" = mkSecret "${name}.pem";
        "etcd-key.pem" = mkSecret "${name}-key.pem";
        "etcd-peer.pem" = mkSecret "${name}-peer.pem";
        "etcd-peer-key.pem" = mkSecret "${name}-peer-key.pem";
    };
}
