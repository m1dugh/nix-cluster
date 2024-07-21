{
    pkgs,
    lib,
    masterHosts,
    extraSANs ? [],
    workerHosts,
    cfssl,
    cfssljson,
    ...
}:
with lib;
let
    inherit (pkgs.callPackage ./lib.nix {}) mkCsr mkProfile applyNodeConfig;
    caConf = mkCsr "k8s-cluster" {
        cn = "kubernetes";
        organization = "k8s-cluster";
    };

    apiServerCsr = mkCsr "apiserver" 
    (let
        extraHosts = lists.concatMap (n: [n.name n.address]) masterHosts;
    in {
        cn = "kubernetes";
        hosts = extraSANs
        ++ extraHosts
        ++ [
            "127.0.0.1"
            "10.32.0.1"
            "kubernetes"
            "kubernetes.default"
            "kubernetes.default.svc"
            "kubernetes.default.svc.cluster"
            "kubernetes.default.svc.cluster.local"
        ];
    });

    adminCsr = mkCsr "admin" {
        cn = "admin";
        organization = "system:masters";
    };

    saCsr = mkCsr "service-accounts" {
        cn = "service-accounts";
    };

    mkNodeCsr = {
        name,
        address,
        ...
    }
    : mkCsr name {
        cn = "system:node:${name}";
        organization = "system:nodes";
        hosts = [
            name
            address
            "127.0.0.1"
        ];
    };

    proxyCsr = mkCsr "kube-proxy" {
        cn = "system:kube-proxy";
        organization = "system:node-proxier";
        hosts = [
            "kube-proxy"
            "127.0.0.1"
        ];
    };

    controllerManagerCsr = mkCsr "kube-controller-manager" {
        cn = "system:kube-controller-manager";
        organization = "system:kube-controller-manager";
        hosts = [
            "kube-proxy"
            "127.0.0.1"
        ];
    };

    schedulerCsr = mkCsr "kube-scheduler" {
        cn = "system:kube-scheduler";
        organization = "system:kube-scheduler";
        hosts = [
            "kube-proxy"
            "127.0.0.1"
        ];
    };

    profile = mkProfile "k8s-client-profile" {
        client = [
            "signing"
            "key encipherment"
            "client auth"
        ];
        server = [
            "signing"
            "key encipherment"
            "client auth"
            "server auth"
        ];
    };
    mkNodeConfig = node: "genCert server ${profile} ${node.name} ${mkNodeCsr node}";
in ''
mkdir -p kubernetes
(
cd kubernetes

genCa ${caConf}

genCert client ${profile} admin ${adminCsr}
${applyNodeConfig workerHosts mkNodeConfig}
genCert server ${profile} kube-proxy ${proxyCsr}
genCert server ${profile} kube-scheduler ${schedulerCsr}
genCert server ${profile} kube-controller-manager ${controllerManagerCsr}
genCert server ${profile} kube-api-server ${apiServerCsr}
genCert client ${profile} service-accounts ${saCsr}

)
toJsonCerts kubernetes
''
