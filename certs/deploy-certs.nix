{ etcdHosts
, etcdOwner ? "etcd"
, masterHosts
, workerHosts
, lib
, pkgs
, ...
}:
with lib;
let
  inherit (pkgs.callPackage ./lib.nix {}) applyNodeConfig;
  scp = "${pkgs.openssh}/bin/scp";
  ssh = "${pkgs.openssh}/bin/ssh";
  pushEtcdCerts = {
  name,
  address,
  ...
  }: ''
  folder=$out/etcd/
  outfolder=/var/lib/etcd/ssl/
  ${ssh} root@${address} mkdir -p $outfolder

  ${scp} $folder/ca.pem $folder/${name}.pem $folder/${name}-key.pem \
      $folder/${name}-peer.pem $folder/${name}-peer-key.pem \
      root@${address}:$outfolder
  ${ssh} root@${address} chown -R ${etcdOwner}:${etcdOwner} $outfolder
  '';
  pushMasterCerts = {
  address,
  ...
  }: ''
  folder=$out/kubernetes/
  outfolder=/var/lib/kubernetes/ssl/
  ${ssh} root@${address} mkdir -p $outfolder

  ${scp} $folder/ca.pem $folder/ca-key.pem \
      $folder/kube-api-server.pem $folder/kube-api-server-key.pem \
      $folder/service-accounts.pem $folder/service-accounts-key.pem \
      root@${address}:$outfolder
  '';
  pushWorkerCerts = {
  name,
  address,
  ...
  }: ''
  folder=$out/kubernetes/
  outfolder=/var/lib/kubelet/
  ${ssh} root@${address} mkdir -p $outfolder

  ${scp} $folder/ca.pem root@${address}:$outfolder
  ${scp} $folder/${name}.pem root@${address}:$outfolder/kubelet.pem
  ${scp} $folder/${name}-key.pem root@${address}:$outfolder/kubelet-key.pem
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
+ applyNodeConfig masterHosts pushMasterCerts
+ applyNodeConfig workerHosts pushWorkerCerts
)
