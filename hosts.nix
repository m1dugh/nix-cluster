let
  enable = true;
in
{
    deploymentConfig = {
        "192.168.1.145" = {
            address = "10.200.0.1";
        };
        "192.168.1.146" = {
            address = "10.200.0.2";
        };
        "192.168.1.147" = {
            address = "10.200.0.3";
        };
        "192.168.1.148" = {
            address = "10.200.0.4";
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
      name = "cluster-master-4";
      address = "192.168.1.148";
      etcd.enable = false;
      worker = enable;
      master = false;
    }
  ];
}
