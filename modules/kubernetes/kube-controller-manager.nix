{ config
, ...
}:
let cfg = config.midugh.kubernetes;
in {

  services.kubernetes.controllerManager = {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/controller-manager.key";
      certFile = "${cfg.pkiRootDir}/controller-manager.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
    rootCaFile = "${cfg.pkiRootDir}/ca.crt";
    serviceAccountKeyFile = "${cfg.pkiRootDir}/sa.key";

    extraOpts = [
      "--cluster-signing-key-file=${cfg.pkiRootDir}/ca.key"
      "--client-ca-file=${cfg.pkiRootDir}/ca.crt"
      "--cluster-signing-cert-file=${cfg.pkiRootDir}/ca.crt"
      "--requestheader-client-ca-file=${cfg.pkiRootDir}/front-proxy-ca.crt"
    ];
  };
}
