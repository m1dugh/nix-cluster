{ nodeConfig
, lib
, ...
}:
with lib;
let
  inherit (nodeConfig) name;
  mkSecret = filename: rec {
    keyFile = ../../generated-certs/kubernetes/${filename};
    destDir = "/var/lib/kubernetes/ssl/";
    user = "kubernetes";
    group = user;
    permissions = "0400";
  };
in
{
  deployment.keys = mkIf nodeConfig.worker ((attrsets.genAttrs [
    "ca.pem"
    "kube-proxy.pem"
    "kube-proxy-key.pem"
  ]
    mkSecret) // {
    "kubelet.pem" = mkSecret "${name}.pem";
    "kubelet-key.pem" = mkSecret "${name}-key.pem";
    "front-proxy-ca.pem" = (mkSecret "front-proxy-ca.pem") // {
        keyFile = ../../generated-certs/kubernetes/front-proxy/ca.pem;
    };
  });
}
