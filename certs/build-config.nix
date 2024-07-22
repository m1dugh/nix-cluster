{ pkgs
, lib
, apiserver
, ...
}:
with lib;
let
  k = "${pkgs.kubectl}/bin/kubectl";
  clusterName = "k8s-cluster";
  userName = "admin";
  address = "https://${apiserver.address}:${toString apiserver.port}";
in
pkgs.writeShellScriptBin "build-config" ''
  set -e
  folder=''${1:-./generated-certs/kubernetes}

  ${k} config set-cluster ${clusterName} \
      --certificate-authority=$folder/ca.pem \
      --embed-certs=true \
      --server=${address} \
      --kubeconfig=admin.kubeconfig

  ${k} config set-credentials ${userName} \
      --client-certificate=$folder/admin.pem \
      --client-key=$folder/admin-key.pem \
      --embed-certs=true \
      --kubeconfig=admin.kubeconfig

  ${k} config set-context default \
      --cluster=${clusterName} \
      --user=${userName} \
      --kubeconfig=admin.kubeconfig

  ${k} config use-context default \
      --kubeconfig=admin.kubeconfig
''
