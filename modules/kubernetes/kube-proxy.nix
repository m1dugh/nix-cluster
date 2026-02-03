{ config
, lib
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  config.services.kubernetes.proxy = lib.mkIf (cfg.enable) {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/kube-proxy.key";
      certFile = "${cfg.pkiRootDir}/kube-proxy.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
  };
}
