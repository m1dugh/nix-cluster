{
    pkgs,
    lib,
    hosts ? [], # Hosts is a list containing for each node a cn and a list of altName
    cfssl,
    cfssljson,
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
            "server auth"
        ];
    in {
        server = defaultUsages;
        client = defaultUsages;
        peer = defaultUsages ++ ["client auth"];
    });
    clientCsr = mkCsr "client-csr" {
        cn = "client";
    };
    genHost = host: 
    let csr = mkCsr host.cn {
        inherit (host) cn;
        hosts = [ host.cn ] ++ host.altNames;
    };
    in ''
    genCert server ${profile} ${host.cn} ${csr}
    genCert peer ${profile} ${host.cn}-peer ${csr}
    '';
    commands = builtins.map genHost hosts;
in (''
mkdir -p etcd
(
cd etcd

genCa ${caConf}

'' + strings.concatStringsSep "\n" commands
+ ''
genCert client ${profile} client ${clientCsr}
)
'')
