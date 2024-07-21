{
    pkgs,
    lib,
    etcdHosts,
    cfssl,
    cfssljson,
    jq,
    ...
}:
with lib;
let
    inherit (pkgs.callPackage ./lib.nix {}) mkCsr mkProfile;
    caConf = mkCsr "default" {
        cn = "etcd-cluster";
        organization = "k8s-cluster";
    };
    profile = mkProfile "etcd-profile" (
    let
        defaultUsages = [
            "signing"
            "key encipherment"
        ];
    in {
        server = defaultUsages ++ ["server auth"];
        client = defaultUsages ++ ["client auth"];
        peer = defaultUsages ++ ["client auth" "server auth"];
    });
    clientCsr = mkCsr "client-csr" {
        cn = "client";
    };
    genHost = {
        cn,
        altNames,
        ...
    }: 
    let csr = mkCsr cn {
        inherit cn;
        hosts = [ cn ] ++ altNames;
    };
    in ''
    genCert server ${profile} ${cn} ${csr}
    genCert peer ${profile} ${cn}-peer ${csr}
    '';
    commands = builtins.map genHost etcdHosts;
in (''
mkdir -p etcd
(
cd etcd

genCa ${caConf}

'' + strings.concatStringsSep "\n" commands
+ ''
genCert client ${profile} client ${clientCsr}

)
toJsonCerts etcd
'')
