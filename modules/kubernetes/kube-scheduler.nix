{ config
, lib
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  config.services.kubernetes.scheduler = lib.mkIf (cfg.enable && cfg.master.enable) {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/scheduler.key";
      certFile = "${cfg.pkiRootDir}/scheduler.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
  };
}
