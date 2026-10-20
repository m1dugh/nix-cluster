# Nix cluster

This project runs a full infrastructure under kubernetes as home lab.

## Infrastructure

### Network

There are 2 subnets : 

| range | vlan | description |
| ----- | ---- | ----------- |
| 192.168.1.0/24 | 1 | The home vlan, it should be considered as WAN |
| 192.168.2.0/24 | 10 | The actual infra vlan |

### Hosts

The infrastructure is composed of 4 hosts :

| vlan:ips | name | role | server type |
| -------- | ---- | ---- | ----------- |
| 1:192.168.1.145,10:192.168.2.1 | cluster-router | In charge of routing and security between infra and wan | raspi4 4G |
| 2:192.168.2.11 | cluster-master-1 | The master of the kubernetes cluster | raspi4 8G |
| 2:192.168.2.21 | cluster-worker-1 | The first worker of the kubernetes cluster | raspi4 8G |
| 2:192.168.2.22 | cluster-worker-2 | The second worker of the kubernetes cluster | raspi4 8G |

### Technical stack

#### cluster-router

`cluster-router` is the router in this infra.

This router is fully configured via nixos and colmena.

it will hold the following service :

- dhcp server for the infra lan
- netboot server for the infra lan
- routing via vlan tagged interface
- firewall via nftables
- loadbalancer via haproxy
- wireguard on the wan.

All of these services are under the `nix/services` folder

#### cluster master/workers

All the kubernetes nodes are running kubernetes using talos kubernetes
distribution. The images are stored on `cluster-router` and served via netboot.

The actual cluster setup is manual through talosctl.
