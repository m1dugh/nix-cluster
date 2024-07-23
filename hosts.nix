let
  enable = true;
in
{
  apiserver = {
    address = "192.168.1.145";
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
