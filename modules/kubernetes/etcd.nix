{ config
, lib
, ...
}:
let
  cfg = config.midugh.kubernetes;
  etcdDataDir = cfg.pkiRootDir + "/etcd";
in
{
  config.services.etcd = lib.mkIf (cfg.enable && cfg.master.enable) {
    enable = true;
    trustedCaFile = etcdDataDir + "/ca.crt";
    clientCertAuth = true;
    peerTrustedCaFile = etcdDataDir + "/ca.crt";
    keyFile = etcdDataDir + "/server.key";
    certFile = etcdDataDir + "/server.crt";
    peerKeyFile = etcdDataDir + "/peer.key";
    peerCertFile = etcdDataDir + "/peer.crt";
    openFirewall = true;
  };
}
