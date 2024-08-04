{ etcdHosts
, masterHosts
, workerHosts
, lib
, deploymentConfig
, pkgs
, ...
}:
with lib;
let
    mkUrl = address:
    if deploymentConfig == null || (! attrsets.hasAttrByPath [address] deploymentConfig) then
        "root@${address}"
    else
    let
        entry = deploymentConfig.${address};
        destAddress = if attrsets.hasAttrByPath ["address"] entry then
            entry.address
        else
            address
        ;
    in
        "root@${destAddress}"
    ;
  scp = "${pkgs.openssh}/bin/scp";
  ssh = "${pkgs.openssh}/bin/ssh";
  k8sDataPath = "/var/lib/kubernetes/";
  k8sCertPath = "${k8sDataPath}/ssl/";
  etcdDataPath = "/var/lib/etcd/";
  etcdCertPath = "${etcdDataPath}/ssl/";
  cniConfigPath = "/var/lib/cni/net.d/";
  mkMasterNode =
    { address
    , name
    , ...
    }:
    let
      url = mkUrl address;
    in
    ''
      echo Uploading master certs at ${url} for ${name} >&2
      uploadMasterCerts ${url}
    '';
  mkWorkerNode =
    { address
    , name
    , ...
    }:
    let
      url = mkUrl address;
    in
    ''
      echo Uploading worker certs at ${url} for ${name} >&2
      uploadWorkerCerts ${url} ${name}
    '';
  mkEtcdNode =
    { address
    , name
    , ...
    }:
    let
      url = mkUrl address;
    in
    ''
      echo Uploading etcd certs at ${url} for ${name} >&2
      uploadEtcdCerts ${url} ${name}
    '';
  etcdLines = builtins.map mkEtcdNode etcdHosts;
  masterLines = builtins.map mkMasterNode masterHosts;
  workerLines = builtins.map mkWorkerNode workerHosts;
  configLines =
    etcdLines
    ++ masterLines
    ++ workerLines;
in
pkgs.writeShellScriptBin "deploy-certs" (''

out=''${1:-./generated-certs}
etcdDir="$out/etcd/"
k8sDir="$out/kubernetes/"

function remoteMkdir() {
    url="$1"
    path="$2"
    ${ssh} $url mkdir -p $path
}

function uploadEtcdCerts () {
    url="$1"
    node="$2"
    remoteMkdir $url ${etcdCertPath}
    ${ssh} $url chown etcd:etcd ${etcdDataPath}

    ${scp} $etcdDir/ca.pem $url:${etcdCertPath}
    ${scp} $etcdDir/$node.pem $url:${etcdCertPath}/etcd.pem
    ${scp} $etcdDir/$node-key.pem $url:${etcdCertPath}/etcd-key.pem

    ${scp} $etcdDir/$node-peer.pem $url:${etcdCertPath}/etcd-peer.pem
    ${scp} $etcdDir/$node-peer-key.pem $url:${etcdCertPath}/etcd-peer-key.pem

    ${ssh} $url chown -R etcd:etcd ${etcdCertPath}
    ${ssh} $url chmod 400 ${etcdCertPath}/*.pem
}

function uploadMasterCerts () {
    url="$1"
    remoteMkdir $url ${k8sCertPath}
    ${ssh} $url chown kubernetes:kubernetes ${k8sDataPath}

    ${scp} \
        $k8sDir/ca-key.pem $k8sDir/ca.pem \
        $k8sDir/kube-api-server-key.pem $k8sDir/kube-api-server.pem \
        $k8sDir/kube-scheduler-key.pem $k8sDir/kube-scheduler.pem \
        $k8sDir/service-accounts-key.pem $k8sDir/service-accounts.pem \
        $url:${k8sCertPath}/

    ${scp} $etcdDir/ca.pem $url:${k8sCertPath}/etcd-ca.pem
    ${scp} $etcdDir/client.pem $url:${k8sCertPath}/etcd-client.pem
    ${scp} $etcdDir/client-key.pem $url:${k8sCertPath}/etcd-client-key.pem

    ${ssh} $url chown -R kubernetes:kubernetes ${k8sCertPath}
    ${ssh} $url chmod 400 ${k8sCertPath}/*.pem
}

function uploadWorkerCerts () {
    url="$1"
    node="$2"
    remoteMkdir $url ${k8sCertPath}
    ${ssh} $url chown kubernetes:kubernetes ${k8sDataPath}

    ${scp} $k8sDir/ca.pem \
        $k8sDir/kube-controller-manager.pem $k8sDir/kube-controller-manager-key.pem \
        $k8sDir/kube-proxy.pem $k8sDir/kube-proxy-key.pem \
        $url:${k8sCertPath}/

    remoteMkdir $url ${cniConfigPath}

    ${scp} $k8sDir/calico.kubeconfig \
        $url:${cniConfigPath}/calico-kubeconfig

    ${scp} $k8sDir/$node.pem $url:${k8sCertPath}/kubelet.pem
    ${scp} $k8sDir/$node-key.pem $url:${k8sCertPath}/kubelet-key.pem

    ${ssh} $url chown -R kubernetes:kubernetes ${k8sCertPath}
    ${ssh} $url chmod 400 ${k8sCertPath}/*.pem
}
''
  + strings.concatStringsSep "\n" configLines
)
