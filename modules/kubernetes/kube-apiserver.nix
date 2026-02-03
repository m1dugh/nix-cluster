{ config
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  services.kubernetes.apiserver = {
    enable = true;
    etcd.caFile = "${cfg.pkiRootDir}/etcd/ca.crt";
    etcd.keyFile = "${cfg.pkiRootDir}/etcd/apiserver-etcd-client.key";
    etcd.certFile = "${cfg.pkiRootDir}/etcd/apiserver-etcd-client.crt";

    clientCaFile = "${cfg.pkiRootDir}/ca.crt";
    tlsKeyFile = "${cfg.pkiRootDir}/apiserver.key";
    tlsCertFile = "${cfg.pkiRootDir}/apiserver.crt";
    kubeletClientCertFile = "${cfg.pkiRootDir}/apiserver-kubelet-client.crt";
    kubeletClientKeyFile = "${cfg.pkiRootDir}/apiserver-kubelet-client.key";

    proxyClientKeyFile = "${cfg.pkiRootDir}/front-proxy-client.key";
    proxyClientCertFile = "${cfg.pkiRootDir}/front-proxy-client.crt";

    serviceAccountKeyFile = "${cfg.pkiRootDir}/sa.pub";

    extraArgs = [
      "--requestheader-client-ca-file=${cfg.pkiRootDir}/front-proxy-ca.crt"
    ];

  };
}
