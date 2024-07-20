{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.midugh.k8s-cluster;
  etcdConfig = cfg.nodeConfig.etcd;
  etcdTls = etcdConfig.enable && etcdConfig.tls;
  mkEtcdCertPath = name: "/var/lib/etcd/ssl/${name}";
  etcdCaFile = mkEtcdCertPath "ca.pem";
  inherit ((pkgs.callPackage ./lib.nix { }).types) nodeConfigType;
in
{
  options.midugh.k8s-cluster = {
    enable = mkEnableOption "k8s cluster";
    clusterNodes = mkOption {
      type = types.listOf nodeConfigType;
      description = ''
        The list of all the nodes in the cluster
        including the current node.
      '';
    };

    nodeConfig = mkOption {
      type = types.nullOr nodeConfigType;
      description = ''
        The config for this node.
      '';
      default = null;
    };
  };

  config = mkIf cfg.enable {

    assertions = [
        {
            assertion = ! isNull cfg.nodeConfig;
            message = "The node config should not be null";
        }
    ];

    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes
      cri-tools
    ];

    virtualisation.containerd.enable = true;

    networking.firewall =
    let
        etcdFirewall = etcdConfig.enable && etcdConfig.openFirewall;
        etcdPorts = lists.optional etcdFirewall etcdConfig.port ++ lists.optional (etcdFirewall && (! isNull etcdConfig.peerPort)) etcdConfig.peerPort;
    in
    {
        allowedTCPPorts = etcdPorts;
    };

    systemd.services.etcd.environment = mkIf (etcdConfig.enable && etcdConfig.tls) (
    let
        inherit (cfg.nodeConfig) name;
        getPath = name: mkDefault (mkEtcdCertPath name);
    in {
        ETCD_TRUSTED_CA_FILE = mkDefault etcdCaFile;
        ETCD_CERT_FILE = getPath "${name}.pem";
        ETCD_KEY_FILE = getPath "${name}-key.pem";
        ETCD_PEER_TRUSTED_CA_FILE = mkDefault etcdCaFile;
        ETCD_PEER_CERT_FILE = getPath "${name}-peer.pem";
        ETCD_PEER_KEY_FILE = getPath "${name}-peer-key.pem";
    });

    services.etcd = mkIf cfg.nodeConfig.etcd.enable (
      let
        inherit (cfg.nodeConfig) name;
        inherit (cfg.nodeConfig.etcd) port peerPort tls;
        getAddress = nodeConfig:
        let
            etcdAddress = nodeConfig.etcd.address;
        in
        if isNull etcdAddress then
            nodeConfig.address
        else
            etcdAddress
        ;
        address = getAddress cfg.nodeConfig;
        peers = builtins.filter (node: node.etcd.enable && (! isNull node.etcd.peerPort)) cfg.clusterNodes;
        getSCheme = tls: if tls then "https" else "http";
        url = "${getSCheme tls}://${address}:${toString port}";
      in
      lib.mkMerge [
        {
          enable = true;
          inherit name;
          listenClientUrls = [
            url
            "http://127.0.0.1:${toString port}"
          ];

          advertiseClientUrls = lists.singleton url;
        }
        (mkIf (! isNull peerPort) (
          let
            peerUrls = lists.singleton "${getSCheme tls}://${address}:${toString peerPort}";
          in
          {
            initialCluster = builtins.map
              (peer:
                let
                  inherit (peer.etcd) peerPort tls;
                  address = getAddress peer;
                in
                "${peer.name}=${getSCheme tls}://${address}:${toString peerPort}")
              peers;

            initialAdvertisePeerUrls = peerUrls;
            listenPeerUrls = peerUrls;
          }
        ))
        (mkIf tls {
            peerClientCertAuth = true;
            clientCertAuth = true;
        })
      ]
    );
  };
}
