{ config
, ...
}:
let
  cfg = config.midugh.kubernetes;
  etcdDataDir = cfg.pkiRootDir + "/etcd";
in
{
  services.etcd = {
    enable = true;
    trustedCaFile = etcdDataDir + "/ca.crt";
    peerTrustedCaFile = etcdDataDir + "/ca.crt";
    keyFile = etcdDataDir + "/server.key";
    certFile = etcdDataDir + "/server.crt";
    peerKeyFile = etcdDataDir + "/peer.key";
    peerCertFile = etcdDataDir + "/peer.crt";
    openFirewall = true;
    clientCertAuth = true;
  };
}
