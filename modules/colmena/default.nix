{ lib
, config
, ...
}:
let
  cfg = config.midugh.kubernetes;
  nodeName = cfg.nodeName;
  rootPath = cfg.pkiLocalDir;
  nodePath = "${rootPath}/nodes/${nodeName}/";
  mkSecret =
    { name ? null
    , user ? null
    , nodeSpecific ? true
    , etcd ? false
    , permissions ? "0400"
    , extraParams ? { }
    ,
    }:
    let
      basePath = if nodeSpecific then nodePath else rootPath;
      path = if etcd then "${basePath}/etcd/" else basePath;
      destDir = if etcd then "${cfg.pkiRootDir}/etcd/" else cfg.pkiRootDir;
      effectiveUser = if ! (isNull user) then user else if etcd then "etcd" else "kubernetes";
    in
    ({
      inherit destDir name permissions;
      keyCommand = [
        "cat"
        "${path}/${name}"
      ];
      user = effectiveUser;
      group = effectiveUser;
    } // extraParams);
in
{
  deployment.keys."servers.key" = {
    keyCommand = [
      "cat"
      "./secrets/servers.key"
    ];
    destDir = "/var/lib/nixos/";
    group = "root";
    user = "root";
    permissions = "0400";
  };

  deployment.keys."etcd-ca" = lib.mkIf (cfg.enable && config.services.etcd.enable) (mkSecret {
    etcd = true;
    nodeSpecific = false;
    name = "ca.crt";
    permissions = "0644";
  });

  deployment.keys."etcd-key" = lib.mkIf (cfg.enable && config.services.etcd.enable) (mkSecret {
    etcd = true;
    nodeSpecific = false;
    name = "ca.key";
  });

  deployment.keys."etcd-server.key" = lib.mkIf (cfg.enable && config.services.etcd.enable) (mkSecret {
    etcd = true;
    name = "server.key";
  });
  deployment.keys."etcd-server.crt" = lib.mkIf (cfg.enable && config.services.etcd.enable) (mkSecret {
    etcd = true;
    name = "server.crt";
  });
  deployment.keys."etcd-peer.key" = lib.mkIf (cfg.enable && config.services.etcd.enable) (mkSecret {
    etcd = true;
    name = "peer.key";
  });
  deployment.keys."etcd-peer.crt" = lib.mkIf (cfg.enable && config.services.etcd.enable) (mkSecret {
    etcd = true;
    name = "peer.crt";
  });
  deployment.keys."kubernetes-ca" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    nodeSpecific = false;
    name = "ca.crt";
    permissions = "0644";
  });
  deployment.keys."kubernetes-key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    nodeSpecific = false;
    name = "ca.key";
  });

  deployment.keys."kubernetes-sa.pub" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    nodeSpecific = false;
    name = "sa.pub";
  });

  deployment.keys."kubernetes-sa.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    nodeSpecific = false;
    name = "sa.key";
  });
  deployment.keys."apiserver.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "apiserver.crt";
  });
  deployment.keys."apiserver.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "apiserver.key";
  });
  deployment.keys."apiserver-kubelet-client.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "apiserver-kubelet-client.crt";
  });
  deployment.keys."apiserver-kubelet-client.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "apiserver-kubelet-client.key";
  });
  deployment.keys."front-proxy-ca.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    nodeSpecific = false;
    name = "front-proxy-ca.crt";
    permissions = "0644";
  });
  deployment.keys."front-proxy-client.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "front-proxy-client.crt";
  });
  deployment.keys."front-proxy-client.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "front-proxy-client.key";
  });
  deployment.keys."kube-proxy.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "kube-proxy.crt";
  });
  deployment.keys."kube-proxy.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "kube-proxy.key";
  });
  deployment.keys."controller-manager.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "controller-manager.key";
  });
  deployment.keys."controller-manager.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "controller-manager.crt";
  });

  deployment.keys."apiserver-etcd-client.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "apiserver-etcd-client.crt";
  });
  deployment.keys."apiserver-etcd-client.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "apiserver-etcd-client.key";
  });
  deployment.keys."scheduler.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "scheduler.crt";
  });
  deployment.keys."scheduler.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "scheduler.key";
  });
  deployment.keys."kubelet.crt" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "kubelet.crt";
  });
  deployment.keys."kubelet.key" = lib.mkIf (cfg.enable && cfg.master.enable) (mkSecret {
    name = "kubelet.key";
  });
}
