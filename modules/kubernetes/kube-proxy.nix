{ config
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  services.kubernetes.proxy = {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/server.key";
      certFile = "${cfg.pkiRootDir}/server.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
  };
}
