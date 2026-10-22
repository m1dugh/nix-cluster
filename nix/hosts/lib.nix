{
  vlans = {
    wan = {
      id = 1;
      cidr = "192.168.1.0/24";
      gateway = "192.168.1.254";
    };
    infra = {
      id = 10;
      cidr = "192.168.2.0/24";
    };
  };

  hosts = {
    cluster-router = {
      wan = "192.168.1.145";
      infra = "192.168.2.1";
    };
    cluster-master-1.infra = "192.168.2.11";
    cluster-worker-1.infra = "192.168.2.21";
    cluster-worker-2.infra = "192.168.2.22";
  };
}
