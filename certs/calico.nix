{ lib
, pkgs
, ...
}:
let
  inherit (./lib.nix) mkCsr mkProfile;
  k = "${lib.getExe pkgs.kubectl}";
  caConf = mkCsr "typhaca" {
    cn = "Calico Typha CA";
  };

  profile = mkProfile "typha-profile" {
    default = [
      "signing"
      "key encipherment"
      "client auth"
      "server auth"
    ];
  };

  typhaCsr = mkCsr "typha" {
    cn = "calico-typha";
  };
in
(
  ''
    mkdir -p calico
    (
    cd calico

    genCa ${caConf}

    ${k} create configmap -n kube-system calico-typha-ca \
        --from-file="thyphaca.pem" \
        --dry-run=client \
        -o yaml > calico-typha-ca-cm.yaml

    genCert default ${profile} typhaca ${typhaCsr}

    ${k} create secret generic -n kube-system calico-typha-certs \
        --from-file=typha.key \
        --from-file=typha.crt \
        --dry-run=client \
        -o yaml > calico-typha-certs.yaml

    )
  ''
)
