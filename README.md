# Nix cluster

This project runs a full infrastructure under kubernetes as home lab.

## Infrastructure

### Network

There are 2 subnets : 

| range | vlan | description |
| ----- | ---- | ----------- |
| 192.168.1.0/24 | 1 | The home vlan, it should be considered as WAN |
| 192.168.2.0/24 | 10 | The actual infra vlan |
| 192.168.3.0/24 | - | The wireguard VPN subnet, gateway (cluster-router) at 192.168.3.1 |

### Published ports

Services exposed on `cluster-router`'s WAN-facing address (`192.168.1.145`,
`vlan-wan`), i.e. VPN access and anything port-forwarded from the cluster
out to the home/WAN side. This table must be updated whenever a service is
published on `cluster-router`.

| address | port | service |
| ------- | ---- | ------- |
| 192.168.1.145 | 22/tcp | SSH |
| 192.168.1.145 | 51820/udp | WireGuard VPN |

### Hosts

The infrastructure is composed of 4 hosts :

| vlan:ips | name | role | server type |
| -------- | ---- | ---- | ----------- |
| 1:192.168.1.145,10:192.168.2.1,wg0:192.168.3.1 | cluster-router | In charge of routing and security between infra and wan | raspi4 4G |
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

### Deploying cluster-router

`cluster-router`'s NixOS configuration is defined once, in
`nix/hosts/cluster-router`, and shared by both deployment flows below
(`nixosConfigurations.cluster-router` and `colmenaHive.cluster-router` both
import the same module list, so they never drift apart).

There are 2 ways to deploy it:

#### 1. Bootstrap (first install, via SD image)

Used the first time the raspi4 is provisioned, when there is no NixOS
already running on it to deploy to over SSH.

```sh
nix build .#packages.aarch64-linux.cluster-router-sd-image
```

Flash the resulting `.img.zst` to the router's SD card (e.g. with `dd` or
`raspi-imager`), insert it into the raspi4, and boot it. Once it is up and
reachable on the network, switch to the colmena flow below for all further
changes.

#### 2. Colmena (ongoing deployment)

Used for every deployment once `cluster-router` is already running NixOS
and reachable over SSH.

```sh
colmena apply --on cluster-router
```

This builds the `nixosConfigurations.cluster-router`-equivalent closure
(via `colmenaHive`) and activates it on the live host over SSH, using the
`deployment.targetHost` / `deployment.targetUser` set in the flake.
