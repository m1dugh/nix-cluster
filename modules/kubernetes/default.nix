{ config
, lib
, pkgs
, ...
}:
with lib;
let
  inherit (pkgs.callPackage ../../lib { }) mkApiserverAddress getEtcdNodes mkScheme mkEtcdEndpoint mkEtcdAddress writeJSONText;
  cfg = config.midugh.k8s-cluster;
  etcdConfig = cfg.nodeConfig.etcd;
  inherit (cfg.nodeConfig) master worker name;
  k8sNode = master || worker;
  inherit ((pkgs.callPackage ./lib.nix { }).types) nodeConfigType apiserverConfigType etcdConfigType;
  mkK8sCert = path: "/var/lib/kubernetes/ssl/${path}";
  mkEtcdCert = path: "/var/lib/etcd/ssl/${path}";
  server = mkApiserverAddress cfg.apiserver;
  etcdNodes = getEtcdNodes cfg.clusterNodes;
  etcdEndpoints = builtins.map mkEtcdEndpoint etcdNodes;
in
{
  options.midugh.k8s-cluster = {
    enable = mkEnableOption "k8s cluster";

    cni = mkOption {
        type = types.enum ["calico" "flannel"];
        default = "calico";
        description = "The cni backend to use";
    };

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

  imports = [
    ./calico.nix
    ./flannel.nix
  ];

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

    services.calico-felix = mkIf worker {
        enable = (cfg.cni == "calico");
        etcd = {
            endpoints = etcdEndpoints;
            keyFile = mkK8sCert "etcd-client-key.pem";
            certFile = mkK8sCert "etcd-client.pem";
            caFile = mkK8sCert "etcd-ca.pem";
        };
    };

    services.flannel.etcd = mkIf worker {
        endpoints = etcdEndpoints;
        keyFile = mkK8sCert "etcd-client-key.pem";
        certFile = mkK8sCert "etcd-client.pem";
        caFile = mkK8sCert "etcd-ca.pem";
    };

    systemd.services.rbac-manifests-init-scripts =
    let
        k = "${pkgs.kubectl}/bin/kubectl";
    in mkIf (worker && cfg.nodeConfig.initService.enable) {
        path = with pkgs; [
            kubectl
        ];
        script = ''
        set -e
        ${k} apply --validate=false -f ${./manifests/apiserver-to-kubelet.yaml}
        '';

        serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
        };

        after = [
            "kubelet.service"
        ];

        environment = with cfg.nodeConfig.initService; {
            KUBECONFIG = kubeconfig;
        };

        unitConfig.Description = "a script applying basic rbac for kubernetes";

        wantedBy = [
            "multi-user.target"
        ];
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

        apiserver = mkIf master
          {
            enable = true;
            clientCaFile = caFile;
            etcd = {
              servers = etcdEndpoints;
              keyFile = mkK8sCert "etcd-client-key.pem";
              certFile = mkK8sCert "etcd-client.pem";
              caFile = mkK8sCert "etcd-ca.pem";
            };

            authorizationMode = ["RBAC" "Node"];

            kubeletClientKeyFile = mkK8sCert "kube-api-server-key.pem";
            kubeletClientCertFile = mkK8sCert "kube-api-server.pem";
            kubeletClientCaFile = mkK8sCert "ca.pem";

            serviceAccountSigningKeyFile = mkK8sCert "service-accounts-key.pem";
            serviceAccountKeyFile = mkK8sCert "service-accounts.pem";
            serviceAccountIssuer = server;
            inherit (cfg.apiserver) serviceClusterIpRange;
            tlsCertFile = mkK8sCert "kube-api-server.pem";
            tlsKeyFile = mkK8sCert "kube-api-server-key.pem";
          };

        kubelet = 
        let
            certFile = mkK8sCert "kubelet.pem";
            keyFile = mkK8sCert "kubelet-key.pem";
        in mkIf worker {
          enable = true;

          unschedulable = false;
          taints = mkIf master {
            "node.kubernetes.io/controlplane" = {
                value = "true";
                effect = "NoSchedule";
            };
          };
          kubeconfig = {
            inherit server caFile certFile keyFile;
          };

          clientCaFile = mkK8sCert "ca.pem";
          tlsCertFile = certFile;
          tlsKeyFile = keyFile;

          containerRuntimeEndpoint = "unix:///run/containerd/containerd.sock";
          extraOpts = "--fail-swap-on=false";

          cni.configDir = "/etc/cni/.net.d.wrapped/";
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
