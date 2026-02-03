{ config
, lib
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  config.services.kubernetes.apiserver = lib.mkIf (cfg.enable && cfg.master.enable) {
    enable = true;
    etcd.caFile = "${cfg.pkiRootDir}/etcd/ca.crt";
    etcd.keyFile = "${cfg.pkiRootDir}/apiserver-etcd-client.key";
    etcd.certFile = "${cfg.pkiRootDir}/apiserver-etcd-client.crt";

    clientCaFile = "${cfg.pkiRootDir}/ca.crt";
    tlsKeyFile = "${cfg.pkiRootDir}/apiserver.key";
    tlsCertFile = "${cfg.pkiRootDir}/apiserver.crt";
    kubeletClientCertFile = "${cfg.pkiRootDir}/apiserver-kubelet-client.crt";
    kubeletClientKeyFile = "${cfg.pkiRootDir}/apiserver-kubelet-client.key";

    proxyClientKeyFile = "${cfg.pkiRootDir}/front-proxy-client.key";
    proxyClientCertFile = "${cfg.pkiRootDir}/front-proxy-client.crt";

    serviceAccountKeyFile = "${cfg.pkiRootDir}/sa.pub";
    serviceAccountSigningKeyFile = "${cfg.pkiRootDir}/sa.key";

    extraOpts = "--requestheader-client-ca-file=${cfg.pkiRootDir}/front-proxy-ca.crt";

  };

    config.networking.firewall.allowedTCPPorts = lib.lists.optional (cfg.enable && cfg.master.enable) config.services.kubernetes.apiserver.securePort;
}
