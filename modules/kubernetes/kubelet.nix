{ config
, lib
, ...
}:
let cfg = config.midugh.kubernetes;
in {
  config = lib.mkIf (cfg.enable) {
        networking.firewall.allowedTCPPorts = [ config.services.kubernetes.kubelet.port ];
        services.kubernetes.kubelet = {
            unschedulable = false;
            tlsCertFile = "${cfg.pkiRootDir}/kubelet.crt";
            tlsKeyFile = "${cfg.pkiRootDir}/kubelet.key";
            clientCaFile = "${cfg.pkiRootDir}/ca.crt";
            taints.master-taint = lib.mkIf (!cfg.master.schedulable) {
                key = "node-role.kubernetes.io/control-plane";
                value = "";
                effect = "NoSchedule";
            };
            enable = true;
            kubeconfig = {
                keyFile = "${cfg.pkiRootDir}/kubelet.key";
                certFile = "${cfg.pkiRootDir}/kubelet.crt";
                caFile = "${cfg.pkiRootDir}/ca.crt";
            };
        };
  };
}
