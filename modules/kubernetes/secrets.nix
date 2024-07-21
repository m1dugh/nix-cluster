{
    pkgs,
    lib,
    config,
    ...
}:
with lib;
let
    inherit (pkgs.callPackage ./lib.nix {}) mkEtcdEndpoint;
    certSopsFile = ../../secrets/certs.json;
    secrets = config.sops.secrets;
    cfg = config.midugh.k8s-cluster;
    inherit (cfg) nodeConfig clusterNodes;
    etcdNodes = builtins.filter (node: node.etcd.enable) clusterNodes;
    etcdTls = nodeConfig.etcd.enable && nodeConfig.etcd.tls;
    k8sMaster = nodeConfig.master;
    k8sWorker = nodeConfig.worker;
    k8sNode = k8sMaster || k8sWorker;
    mkCert = {
        section,
        outFolder ? null,
        owner ? null,
        group ? null,
    }: name: {
        "${section}/${name}" = filterAttrs (n: v: v != null) {
            inherit owner group;
            path = mkIf (! isNull outFolder) "${outFolder}/${name}";
            sopsFile = certSopsFile;
        };
    };

    mkEtcdCert = mkCert {
        section = "etcd";
        outFolder = "/var/lib/etcd/ssl";
        owner = "etcd";
        group = "etcd";
    };

    mkK8sCert = mkCert {
        section = "kubernetes";
        owner = "kubernetes";
        group = "kubernetes";
    };

    etcdSection = mkIf etcdTls (mkMerge [
        (mkEtcdCert "ca.pem")
        (mkEtcdCert "client.pem")
        (mkEtcdCert "client-key.pem")
        (mkEtcdCert "${nodeConfig.name}.pem")
        (mkEtcdCert "${nodeConfig.name}-key.pem")
        (mkEtcdCert "${nodeConfig.name}-peer.pem")
        (mkEtcdCert "${nodeConfig.name}-peer-key.pem")
        {
            kubernetes-etcd-ca = {
                owner = "kubernetes";
                group = "kubernetes";
                key = "etcd/ca.pem";
                sopsFile = certSopsFile;
            };
            kubernetes-etcd-client = {
                owner = "kubernetes";
                group = "kubernetes";
                key = "etcd/client.pem";
                sopsFile = certSopsFile;
            };

            kubernetes-etcd-client-key = {
                owner = "kubernetes";
                group = "kubernetes";
                key = "etcd/client-key.pem";
                sopsFile = certSopsFile;
            };
        }
    ]);

    k8sMasterSection =
    let
        components = [
            "ca"
            "kube-api-server"
            "service-accounts"
            "kube-controller-manager"
            "kube-proxy"
            "kube-scheduler"
        ];

    in mkIf k8sMaster (mkMerge (lists.concatMap (el: [
        (mkK8sCert "${el}.pem")
        (mkK8sCert "${el}-key.pem")
    ]) components));

    k8sWorkerSection = mkIf k8sWorker (mkMerge [
        (mkK8sCert "ca.pem")
        (mkK8sCert "${nodeConfig.name}.pem")
        (mkK8sCert "${nodeConfig.name}-key.pem")
    ]);
    mkEtcdSecret = name: secrets."etcd/${name}".path;
    mkKubeSecret = name: secrets."kubernetes/${name}".path;
    server = "https://${cfg.apiserver.address}:${toString cfg.apiserver.port}";
in {
    config = mkIf cfg.enable {
        sops.secrets = lib.mkMerge [
            etcdSection
            k8sMasterSection
            k8sWorkerSection
        ];

        services.kubernetes = mkIf k8sNode (
        let
            caFile = mkKubeSecret "ca.pem";
            mkConfig = role: name: mkIf role {
                enable = true;
                kubeconfig = {
                    inherit server caFile;
                    certFile = mkKubeSecret "${name}.pem";
                    keyFile = mkKubeSecret "${name}-key.pem";
                };
            };
        in {
            kubelet = mkConfig k8sWorker nodeConfig.name;
            proxy = mkConfig k8sMaster "kube-proxy";
            controllerManager = mkConfig k8sMaster "kube-controller-manager";
            scheduler = mkConfig k8sMaster "kube-scheduler";

            apiserver = mkIf k8sMaster (
            let
                servers = builtins.map mkEtcdEndpoint etcdNodes;
            in {
                enable = true;
                clientCaFile = caFile;
                etcd = {
                    inherit servers;
                    keyFile = config.sops.secrets.kubernetes-etcd-client-key.path;
                    certFile = config.sops.secrets.kubernetes-etcd-client.path;
                    caFile = config.sops.secrets.kubernetes-etcd-ca.path;
                };
                kubeletClientKeyFile = mkKubeSecret "kube-api-server-key.pem";
                kubeletClientCertFile = mkKubeSecret "kube-api-server.pem";
                kubeletClientCaFile = mkKubeSecret "ca.pem";

                serviceAccountSigningKeyFile = mkKubeSecret "service-accounts-key.pem";
                serviceAccountKeyFile = mkKubeSecret "service-accounts.pem";
                serviceAccountIssuer = server;
                inherit (cfg.apiserver) serviceClusterIpRange;
                tlsCertFile = mkKubeSecret "kube-api-server.pem";
                tlsKeyFile = mkKubeSecret "kube-api-server-key.pem";
            });
        });

        services.etcd = mkIf etcdTls {
            peerClientCertAuth = true;
            clientCertAuth = true;
            trustedCaFile = mkEtcdSecret "ca.pem";
            certFile = mkEtcdSecret "${nodeConfig.name}.pem";
            keyFile = mkEtcdSecret "${nodeConfig.name}-key.pem";
            peerTrustedCaFile = mkEtcdSecret "ca.pem";
            peerCertFile = mkEtcdSecret "${nodeConfig.name}-peer.pem";
            peerKeyFile = mkEtcdSecret "${nodeConfig.name}-peer-key.pem";
        };
    };
}
