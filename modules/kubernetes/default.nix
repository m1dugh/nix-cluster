{ config
, lib
, pkgs
, ...
}:
with lib;
let
  inherit (pkgs.callPackage ../../lib { }) mkApiserverAddress getEtcdNodes mkScheme mkEtcdEndpoint mkEtcdAddress;
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
        etcdPorts = lists.optionals etcdFirewall [ etcdConfig.port etcdConfig.peerPort ];
        k8sWorkerPorts = lists.optionals worker (with config.services.kubernetes; [
          controllerManager.securePort
          kubelet.port
        ]);
        k8sMasterPorts = lists.optionals master (with config.services.kubernetes; [
          scheduler.port
          apiserver.securePort
        ]);
      in
      {
        allowedTCPPorts = etcdPorts ++ k8sWorkerPorts ++ k8sMasterPorts;
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
        clusterCidr = "10.96.0.0/16";
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

        kubelet = mkIf worker {
          enable = true;
          kubeconfig = {
            inherit server caFile;
            certFile = mkDefault (mkK8sCert "kubelet.pem");
            keyFile = mkDefault (mkK8sCert "kubelet-key.pem");
          };

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
        };
      }
    );


    services.etcd = mkIf cfg.nodeConfig.etcd.enable (
      let
        inherit (cfg.nodeConfig) name;
        inherit (cfg.nodeConfig.etcd) port peerPort tls;
        address = mkEtcdAddress cfg.nodeConfig;
        peers = getEtcdNodes cfg.clusterNodes;
        url = mkEtcdEndpoint cfg.nodeConfig;
      in
      lib.mkMerge [
        (
          let
            peerUrls = lists.singleton "${mkScheme tls}://${address}:${toString peerPort}";
          in
          {
            enable = true;
            inherit name;
            listenClientUrls = [
              url
              "http://127.0.0.1:${toString port}"
            ];

            initialCluster = builtins.map
              (peer:
                let
                  inherit (peer.etcd) peerPort tls;
                  address = mkEtcdAddress peer;
                in
                "${peer.name}=${mkScheme tls}://${address}:${toString peerPort}")
              peers;

            initialAdvertisePeerUrls = peerUrls;
            listenPeerUrls = peerUrls;

            advertiseClientUrls = lists.singleton url;
          }
        )
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
      ]
    );
  };
}
