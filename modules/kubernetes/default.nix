{ config
, lib
, pkgs
, ...
}:
with lib;
let
  inherit (pkgs.callPackage ../../lib { }) mkApiserverAddress getEtcdNodes mkScheme mkEtcdEndpoint;
  cfg = config.midugh.k8s-cluster;
  etcdConfig = cfg.nodeConfig.etcd;
  inherit (cfg.nodeConfig) master worker;
  k8sNode = master || worker;
  inherit ((pkgs.callPackage ./lib.nix { }).types) nodeConfigType apiserverConfigType etcdConfigType;
  mkK8sCert = path: "/var/lib/kubernetes/ssl/${path}";
  mkEtcdCert = path: "/var/lib/etcd/ssl/${path}";
  server = mkApiserverAddress cfg.apiserver;
  etcdNodes = getEtcdNodes cfg.clusterNodes;
in
{
  options.midugh.k8s-cluster = {
    enable = mkEnableOption "k8s cluster";
    etcd = mkOption {
      type = etcdConfigType;
      description = "The config of the etcd service";
      default = {
        port = 2379;
      };
    };

    apiserver = mkOption {
      type = apiserverConfigType;
      description = "The config of the k8s service";
      default = {
        port = 6443;
      };
    };

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


    environment.systemPackages = with pkgs;
      (lists.optionals k8sNode [
        kubectl
        kubernetes
        cri-tools
        calico-cni-plugin
      ]);

    virtualisation.containerd = mkIf worker {
      enable = true;
      settings.plugins = {
        "io.containerd.internal.v1.opt".path = "/var/lib/containerd/opt";
        "io.containerd.grpc.v1.cri" = {
          sandbox_image = "registry.k8s.io/pause:3.9";

          containerd = {
            snapshotter = "overlayfs";
            runtimes.runc.options.SystemdCgroup = true;
          };
        };
      };
    };

    networking.firewall =
      let
        etcdFirewall = etcdConfig.enable && etcdConfig.openFirewall;
        etcdPorts = lists.optional etcdFirewall etcdConfig.port ++ lists.optional (etcdFirewall && (! isNull etcdConfig.peerPort)) etcdConfig.peerPort;
        k8sPorts = (lists.optional master 6443);
      in
      {
        allowedTCPPorts = etcdPorts ++ k8sPorts;
      };

    services.kubernetes = mkIf k8sNode (
      let
        caFile = mkK8sCert "ca.pem";
        mkConfig = role: component: mkIf role {
          enable = true;
          kubeconfig = {
            inherit server caFile;
            certFile = mkDefault (mkK8sCert "${component}.pem");
            keyFile = mkDefault (mkK8sCert "${component}-key.pem");
          };
        };
      in
      {
        proxy = mkConfig worker "kube-proxy";
        controllerManager = mkConfig worker "kube-controller-manager";
        scheduler = mkConfig master "kube-scheduler";

        apiserver = mkIf master (
          let
            servers = builtins.map mkEtcdEndpoint etcdNodes;
          in
          {
            enable = true;
            clientCaFile = caFile;
            etcd = {
              inherit servers;
              keyFile = mkK8sCert "etcd-client-key.pem";
              certFile = mkK8sCert "etcd-client.pem";
              caFile = mkK8sCert "etcd-ca.pem";
            };

            kubeletClientKeyFile = mkK8sCert "kube-api-server-key.pem";
            kubeletClientCertFile = mkK8sCert "kube-api-server.pem";
            kubeletClientCaFile = mkK8sCert "ca.pem";

            serviceAccountSigningKeyFile = mkK8sCert "service-accounts-key.pem";
            serviceAccountKeyFile = mkK8sCert "service-accounts.pem";
            serviceAccountIssuer = server;
            inherit (cfg.apiserver) serviceClusterIpRange;
            tlsCertFile = mkK8sCert "kube-api-server.pem";
            tlsKeyFile = mkK8sCert "kube-api-server-key.pem";
          }
        );

        kubelet = mkIf worker (attrsets.recursiveUpdate (mkConfig worker "kubelet") {

          containerRuntimeEndpoint = "unix:///run/containerd/containerd.sock";
          extraOpts = "--fail-swap-on=false";
          cni = {
            packages = with pkgs; [
              calico-cni-plugin
            ];
            config = [
              {
                name = "k8s-pod-network";
                cniVersion = "0.4.0";
                type = "calico";
                plugins = [
                  {
                    type = "calico";
                    log_level = "info";
                    datastore_type = "kubernetes";
                    nodename = "127.0.0.1";
                    ipam = {
                      type = "host-local";
                      subnet = "usePodCidr";
                    };
                    policy.type = "k8s";
                    kubernetes.kubeconfig = "/var/lib/cni/net.d/calico-kubeconfig";
                  }
                  {
                    type = "portmap";
                    capabilities.portMappings = true;
                    externalSetMarkChain = "KUBE-MARK-MASQ";
                  }
                ];
              }
            ];
          };
        });
      }
    );


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
        url = "${mkScheme tls}://${address}:${toString port}";
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
        (mkIf tls {
          peerClientCertAuth = true;
          clientCertAuth = true;
          trustedCaFile = mkEtcdCert "ca.pem";
          certFile = mkEtcdCert "etcd.pem";
          keyFile = mkEtcdCert "etcd-key.pem";
          peerTrustedCaFile = mkEtcdCert "ca.pem";
          peerCertFile = mkEtcdCert "etcd-peer.pem";
          peerKeyFile = mkEtcdCert "etcd-peer-key.pem";
        })
        (mkIf (! isNull peerPort) (
          let
            peerUrls = lists.singleton "${mkScheme tls}://${address}:${toString peerPort}";
          in
          {
            initialCluster = builtins.map
              (peer:
                let
                  inherit (peer.etcd) peerPort tls;
                  address = getAddress peer;
                in
                "${peer.name}=${mkScheme tls}://${address}:${toString peerPort}")
              peers;

            initialAdvertisePeerUrls = peerUrls;
            listenPeerUrls = peerUrls;
          }
        ))
      ]
    );
  };
}
