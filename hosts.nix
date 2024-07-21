{
  masterAddress = "192.168.1.145";
  nodes = [
    {
      name = "cluster-master-1";
      address = "192.168.1.145";
      etcd = {
          peerPort = 2380;
          enable = true;
          openFirewall = true;
          tls = true;
      };
      worker = true;
      master = true;
    }
    {
        name = "cluster-master-2";
        address = "192.168.1.146";
        etcd = {
            peerPort = 2380;
            enable = true;
            openFirewall = true;
            tls = true;
        };
        worker = true;
        master = true;
    }
  ];
}
