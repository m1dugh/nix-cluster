{ config
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  services.kubernetes.kubelet = {
    enable = true;
    kubeconfig = {
      keyFile = "${cfg.pkiRootDir}/kubelet.key";
      certFile = "${cfg.pkiRootDir}/kubelet.crt";
      caFile = "${cfg.pkiRootDir}/ca.crt";
    };
  };
}
