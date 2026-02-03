{ config
, lib
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  config.services.kubernetes.kubelet = lib.mkIf (cfg.enable) {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/kubelet.key";
      certFile = "${cfg.pkiRootDir}/kubelet.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
  };
}
