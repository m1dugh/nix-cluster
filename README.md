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
| 192.168.2.0/24 (vlan-infra) | 50000/tcp | Talos apid (talosctl management API), forwarded from `vlan-wan` |
| 192.168.1.145 (vlan-wan, haproxy) | 6443/tcp | Kubernetes API |
| 192.168.1.161 (vlan-wan, haproxy) | 80/tcp | nginx-gateway-fabric `private-gateway` HTTP, forwarded to its NodePort (30080) |
| 192.168.1.162 (vlan-wan, haproxy) | 80/tcp | nginx-gateway-fabric `public-gateway` HTTP, forwarded to its NodePort (31080) |
| 192.168.1.161 (vlan-wan, haproxy) | 443/tcp | nginx-gateway-fabric `private-gateway` HTTPS (`*.int.midugh.fr`), forwarded to its NodePort (30443) |
| 192.168.1.162 (vlan-wan, haproxy) | 443/tcp | nginx-gateway-fabric `public-gateway` HTTPS (`*.midugh.fr`), forwarded to its NodePort (31443) |

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
- netboot server for the infra lan (currently parked — see the Netboot
  section below; nodes are presently brought up via SD-card flashing)
- routing via vlan tagged interface
- firewall via nftables
- loadbalancer via haproxy
- wireguard on the wan.

All of these services are under the `nix/services` folder

DHCP + TFTP for `vlan-infra` are served by `dnsmasq`, not Kea or an
ISC-DHCP-style server: this is a home-lab-scale setup with a handful of
hosts, and dnsmasq's built-in, purpose-made PXE support (`dhcp-boot`,
`enable-tftp`) is a far better fit than Kea's verbose, carrier-grade JSON
config model — which is built for the scale and operational needs of
large organizations, not a 4-host cluster. Kea was tried first and is a
capable DHCP server, but required reimplementing PXE's option 43 by hand
(it has no native PXE awareness), whereas dnsmasq handles RPi4 netboot
out of the box the way most of the ecosystem already does.

#### cluster master/workers

All the kubernetes nodes are running kubernetes using talos kubernetes
distribution. The images are stored on `cluster-router` and served via netboot.

The actual cluster setup is manual through talosctl.

### Netboot (RPi4 -> Talos) — currently parked

**Not in active use.** After extensive troubleshooting (see AGENTS.md's
Netboot section for the full history), large TFTP transfers (the Talos
kernel/initramfs) were never reliably reachable, so the kubernetes nodes
are currently brought up by flashing Talos directly to SD cards instead.
The implementation below is left in the config, commented out rather than
removed, to resume from later — `services.dnsmasq`'s PXE-specific
settings and the `systemd.tmpfiles.rules` populating `/var/lib/tftpboot`
in `nix/hosts/cluster-router/default.nix`.

`cluster-router` netboots the kubernetes nodes (RPi4) over `vlan-infra`.
This is a two-stage chain, both stages served over **TFTP only** from
`/var/lib/tftpboot` (dnsmasq's built-in TFTP server, port 69/udp):

1. **RPi4 EEPROM firmware -> U-Boot.** The Pi's on-board EEPROM (not the
   SD card) does a DHCP request, learns the TFTP server from dnsmasq's
   `dhcp-boot`, and fetches `start4.elf` / `fixup4.dat` /
   `bcm2711-rpi-4-b.dtb` / `config.txt`, then loads `kernel8.img` (this is
   actually `u-boot.bin` renamed, since the RPi4 firmware only knows how
   to chainload a file by that name). All of these files are built
   declaratively from `pkgs.raspberrypifw` + `pkgs.ubootRaspberryPi4_64bit`
   (see `nix/hosts/cluster-router/default.nix`) and dropped into
   `/var/lib/tftpboot` via `systemd.tmpfiles`.
2. **U-Boot -> Talos.** U-Boot's built-in PXE client (`boot_targets = mmc
   usb pxe dhcp`) does its own DHCP, then fetches
   `pxelinux.cfg/default` (extlinux syntax, declaratively generated) which
   points at `talos/vmlinuz` + `talos/initramfs.xz` with
   `APPEND talos.platform=metal`. The node comes up in Talos **maintenance
   mode** with a DHCP-leased IP; it has no identity (control-plane vs.
   worker, static IP, etc.) until configured with `talosctl apply-config`
   from a workstation that can reach `vlan-infra` (directly or over the
   `wg0` VPN).

The Talos kernel/initramfs themselves are **not** managed by Nix — download
the official Talos metal **arm64** release assets and drop them manually
on `cluster-router`, under `/var/lib/tftpboot/talos/`, named exactly:

| file on cluster-router | source (Talos metal arm64 release asset) |
| ----------------------- | ----------------------------------------- |
| `/var/lib/tftpboot/talos/vmlinuz` | `vmlinuz-arm64` |
| `/var/lib/tftpboot/talos/initramfs.xz` | `initramfs-arm64.xz` |

These names must match `pxelinux.cfg/default`'s `KERNEL`/`INITRD` lines
exactly, since that file is generated by Nix and not meant to be
hand-edited.

#### Manual one-time step per Raspberry Pi

RPi4 ships with network boot disabled in its EEPROM by default; this
**cannot be set from the network side** (it's the very thing that lets
the Pi reach the network in the first place), so each Pi needs one of:

- Boot it once from an SD card (Raspberry Pi OS or just the bootloader
  partition) and run `sudo raspi-config` (Advanced Options -> Boot Order)
  to set network boot first, or `rpi-eeprom-config --edit` directly —
  confirmed via `raspi-config` to produce `BOOT_ORDER=0xf21` for
  network-first, SD fallback — then power-cycle; or
- Use `rpiboot` over USB-C from another machine to push the EEPROM config
  directly, with no SD card involved at all.

After that one-time change, every subsequent boot is network-only.

#### Maintenance mode is one-time, not every boot

U-Boot's default boot order (`boot_targets = mmc usb pxe dhcp`) tries local
storage (SD card / USB disk) *before* falling back to PXE. Each kubernetes
node has local storage with `machine.install.disk` pointing at it in its
Talos machine config, so: first boot -> PXE -> maintenance mode ->
`talosctl apply-config` installs Talos to that disk -> every later reboot,
U-Boot finds the installed disk first and boots from it directly, never
reaching the PXE stage. Without local storage, every reboot would
re-enter maintenance mode with all state wiped — not the setup here.

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
