{
    lib,
    config,
    ...
}:
with lib;
let
    secrets = config.sops.secrets;
    cfg = config.midugh.k8s-cluster;
    nodeConfig = cfg.nodeConfig;
    etcdTls = nodeConfig.etcd.enable && nodeConfig.etcd.tls;
    k8sMaster = nodeConfig.master;
    k8sWorker = nodeConfig.worker;
    mkCert = {
        section,
        outFolder ? null,
        owner ? null,
        group ? null,
    }: name: {
        "${section}/${name}" = filterAttrs (n: v: v != null) {
            inherit owner group;
            path = mkIf (! isNull outFolder) "${outFolder}/${name}";
            sopsFile = ../../secrets/certs.json;
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
    };

    etcdSection = mkIf etcdTls (mkMerge [
        (mkEtcdCert "ca.pem")
        (mkEtcdCert "${nodeConfig.name}.pem")
        (mkEtcdCert "${nodeConfig.name}-key.pem")
        (mkEtcdCert "${nodeConfig.name}-peer.pem")
        (mkEtcdCert "${nodeConfig.name}-peer-key.pem")
    ]);

    k8sMasterSection =
    let
        components = ["ca" "kube-api-server" "service-accounts"];
    in mkIf k8sMaster (mkMerge (lists.concatMap (el: [
        (mkK8sCert "${el}.pem")
        (mkK8sCert "${el}-key.pem")
    ]) components));

    k8sWorkerSection = mkIf k8sWorker (mkMerge [
        (mkK8sCert "ca.pem")
        (mkK8sCert "${nodeConfig.name}.pem")
        (mkK8sCert "${nodeConfig.name}-key.pem")
    ]);
in {
    config = mkIf cfg.enable {
        sops.secrets = lib.mkMerge [
            etcdSection
            k8sMasterSection
            k8sWorkerSection
        ];

        services.etcd = mkIf etcdTls (
        let
            mkEtcdSecret = name: secrets."etcd/${name}".path;
        in {
            peerClientCertAuth = true;
            clientCertAuth = true;
            trustedCaFile = mkEtcdSecret "ca.pem";
            certFile = mkEtcdSecret "${nodeConfig.name}.pem";
            keyFile = mkEtcdSecret "${nodeConfig.name}-key.pem";
            peerTrustedCaFile = mkEtcdSecret "ca.pem";
            peerCertFile = mkEtcdSecret "${nodeConfig.name}-peer.pem";
            peerKeyFile = mkEtcdSecret "${nodeConfig.name}-peer-key.pem";
        });
    };
}
