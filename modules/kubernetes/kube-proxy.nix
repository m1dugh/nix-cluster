{ config
, lib
, ...
}:
let cfg = config.midugh.kubernetes;
in {
    config = lib.mkIf (cfg.enable) {
        services.kubernetes.proxy = {
            enable = true;
            kubeconfig = {
                keyFile = "${cfg.pkiRootDir}/kube-proxy.key";
                certFile = "${cfg.pkiRootDir}/kube-proxy.crt";
                caFile = "${cfg.pkiRootDir}/ca.crt";
            };
        };
        networking.firewall.allowedTCPPorts = [
            10256 # config.services.kubernetes.proxy.port
        ];
    };
}
