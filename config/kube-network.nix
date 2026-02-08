{ ...
}:
{
  
  networking.firewall.interfaces.eth0.allowedTCPPorts = [
        # 5473 # calico typha ports
        7946 # metallb
        30272 # internal http
        31561 # internal https
    ];

  networking.firewall.interfaces.eth0.allowedUDPPorts = [
    8472 # flannel vxlan backend
        7946 # metallb
  ];
  boot.kernelModules = [
    "nf_conntrack"
    "nf_tables"
    "ip_set"
    "ip_set_hash_ip"
    "ip6table_filter"
    "iptable_filter"
    "iptable_nat"
    "br_netfilter"
  ];

}
