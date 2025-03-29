{ nodeConfig
, lib
, ...
}:
with lib;
let
  inherit (nodeConfig) worker master;
  k8sNode = worker || master;
  mkSecret = filename: {
    keyFile = ../../generated-certs/kubernetes/${filename};
    destDir = "/var/lib/coredns/ssl/";
    user = "coredns";
    group = "coredns";
    permissions = "0400";
  };
in
{
  deployment.keys = mkIf k8sNode ((attrsets.genAttrs [
    "coredns.pem"
    "coredns-key.pem"
  ]
    mkSecret) // {
    "coredns-ca.pem" = mkSecret "ca.pem" // {
      name = "ca.pem";
    };
  });
}
