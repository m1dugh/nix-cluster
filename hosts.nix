let
  enable = true;
in
{
  deploymentConfig = {};
  extraConfigs = {
    "cluster-master-1" = {
      midugh.gateway.portForward = [
        {
          sourceInterface = "eth0";
          sourcePort = 80;
          daddr = "192.168.1.145";
          destination = "192.168.1.146:30080";
        }
        {
          sourceInterface = "eth0";
          sourcePort = 443;
          daddr = "192.168.1.145";
          destination = "192.168.1.146:30443";
        }
        {
          sourceInterface = "wg0";
          sourcePort = 80;
          daddr = "10.200.0.1";
          destination = "192.168.1.146:31080";
        }
        {
          sourceInterface = "wg0";
          sourcePort = 443;
          daddr = "10.200.0.1";
          destination = "192.168.1.146:31443";
        }
      ];
      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
    "cluster-master-2" = {
      networking.firewall.allowedTCPPorts = [ 9100 30080 30443 31080 31443 ];
    };
    "cluster-master-3" = {
      networking.firewall.allowedTCPPorts = [ 9100 ];
    };
    "cluster-worker-1" = {
      networking.firewall.allowedTCPPorts = [ 9100 ];
    };
  };
  apiserver = {
    address = "192.168.1.145";
    extraSANs = [
      "10.200.0.1"
    ];
    port = 6443;
    serviceClusterIpRange = "10.32.0.0/24";
  };
  nodes = [
    {
      name = "cluster-master-1";
      address = "192.168.1.145";
      etcd = {
        enable = enable;
        openFirewall = true;
        tls = true;
      };
      worker = false;
      master = enable;
    }
    {
      name = "cluster-master-2";
      address = "192.168.1.146";
      etcd = {
        enable = enable;
        openFirewall = true;
        tls = true;
      };
      worker = enable;
      master = enable;
    }
    {
      name = "cluster-master-3";
      address = "192.168.1.147";
      etcd = {
        enable = enable;
        openFirewall = true;
        tls = true;
      };
      worker = enable;
      master = enable;
    }
    {
      name = "cluster-worker-1";
      address = "192.168.1.148";
      etcd.enable = false;
      worker = enable;
      master = false;
    }
  ];
}
