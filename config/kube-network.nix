{ ...
}:
{
  
  networking.firewall.interfaces.eth0.allowedTCPPorts = [
        # 5473 # calico typha ports
    ];

  networking.firewall.interfaces.eth0.allowedUDPPorts = [
    8472 # flannel vxlan backend
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
