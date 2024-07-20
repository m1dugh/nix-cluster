{ etcdHosts
, etcdOwner ? "etcd"
, lib
, pkgs
, ...
}:
with lib;
let
  scp = "${pkgs.openssh}/bin/scp";
  ssh = "${pkgs.openssh}/bin/ssh";
  applyNodeConfig = nodes: fn: strings.concatStringsSep "\n" (builtins.map fn nodes);
  pushEtcdCerts = {
  name,
  address,
  ...
  }: ''
  folder=$out/etcd/
  ${ssh} root@${address} mkdir -p /var/lib/etcd/ssl/

  ${scp} $folder/ca.pem $folder/${name}.pem $folder/${name}-key.pem \
      $folder/${name}-peer.pem $folder/${name}-peer-key.pem \
      root@${address}:/var/lib/etcd/ssl/
  ${ssh} root@${address} chown -R ${etcdOwner}:${etcdOwner} /var/lib/etcd/ssl/
  '';
in
pkgs.writeShellScriptBin "deploy-certs" (''
  set -e

  out=''${1:-./generated-certs}

  function printerr () {
      echo $* >&2
  }
''
+ applyNodeConfig etcdHosts pushEtcdCerts
)
