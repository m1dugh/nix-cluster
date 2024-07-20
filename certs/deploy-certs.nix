{ nodes
, master
, lib
, pkgs
, ...
}:
with lib;
let
  scp = "${pkgs.openssh}/bin/scp";
  ssh = "${pkgs.openssh}/bin/ssh";
  makeNodeConfig =
    { name
    , address
    , ...
    }: ''
      printerr pushing files for ${name} via ${address}
      ${ssh} root@${address} mkdir -p /var/lib/kubelet/

      ${scp} $out/ca.crt root@${address}:/var/lib/kubelet/

      ${scp} $out/${name}.crt \
          root@${address}:/var/lib/kubelet/kubelet.crt
      ${scp} $out/${name}.key \
          root@${address}:/var/lib/kubelet/kubelet.key
      printerr done !
    '';
  makeMasterConfig =
    { address
    , name
    , ...
    }: ''
      mkdir -p /var/lib/kubernetes/secrets/
      printerr deploying certificates to master ${name} at ${address}

      ${scp} $out/ca.key $out/ca.crt \
          $out/kube-api-server.key $out/kube-api-server.crt \
          $out/service-accounts.key $out/service-accounts.crt \
          root@${address}:/var/lib/kubernetes/secrets/
    '';
in
pkgs.writeShellScriptBin "deploy-certs" (''
  set -e

  out=''${1:-./generated-certs}

  function printerr () {
      echo $* >&2
  }
''
+ strings.concatStringsSep "\n" (builtins.map makeNodeConfig nodes)
  + makeMasterConfig master
)
