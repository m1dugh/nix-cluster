{ config
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  services.kubernetes.scheduler = {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/scheduler.key";
      certFile = "${cfg.pkiRootDir}/scheduler.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
  };
}
