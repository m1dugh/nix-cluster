{ pkgs
, cfssl
, cfssljson
, ...
}:
let
    inherit (pkgs.callPackage ./lib.nix { }) mkCsr mkProfile;
    caConf = mkCsr "k8s-front-proxy" {
        cn = "front-proxy-ca";
        organization = "k8s-cluster";
    };
    frontProxyCsr = mkCsr "front-proxy" {
        cn = "front-proxy-ca";
    };
  profile = mkProfile "k8s-client-profile" {
    kubernetes = [
      "signing"
      "key encipherment"
      "client auth"
      "server auth"
    ];
  };
in ''
mkdir -p kubernetes/front-proxy
(
    cd kubernetes/front-proxy
    genCa ${caConf}
    genCert kubernetes ${profile} front-proxy-client ${frontProxyCsr}
)
''
