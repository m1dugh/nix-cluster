# Nix Cluster

All the technical details are stored in @README.md . Any change in technical
detail **must be stored** in this file.

Current advancement of the project should be stored in the @AGENTS.md file.

## Standing instructions

- Whenever a service is published on `cluster-router`'s WAN-facing address
  (`192.168.1.145`, `vlan-wan`) — VPN access, port-forwarding from the
  cluster, or any other service made reachable from the home/WAN side —
  the "Published ports" table in @README.md must be updated to list the
  bound address, port, and service.
- When committing, no mention of Claude or any other coding agent must be
  added anywhere in the commit — not in the commit message/name, nor in
  its description (e.g. no `Co-Authored-By` lines referencing an agent).
  The same applies to branch names, tag names, and any other git-related
  entity (PR titles/descriptions, etc.).
- Every port published via `cluster-router`'s haproxy load balancer
  (`services.cluster.haproxy.ports`) is reachable from `vlan-wan` by
  default, not just from `vlan-infra`/`wg0` — the nftables `input` chain
  in `nix/hosts/cluster-router/default.nix` generates a `vlan-wan` accept
  rule per haproxy `localPort` automatically (see `wanPublishedPorts` in
  that file's `let` block). This is an `input`-chain rule, not `forward`:
  haproxy listens on the router's own `vlan-infra` address, so this
  traffic terminates at the router rather than being forwarded through
  it (unlike e.g. Talos apid/tcp:50000, which really does forward
  straight to a `vlan-infra` node and so has its own `forward`-chain
  rule). A port must be explicitly excluded from `wanPublishedPorts` to
  keep it off `vlan-wan`; don't assume a haproxy-published port is
  VPN/infra-only without checking that list.
- Do not run `nix build` (or similar) against `cluster-router`'s
  configuration just to validate a change — `colmena apply` will build it
  at deploy time anyway, so a separate local build is redundant busywork.
- Commit messages must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
  `<type>[optional scope]: <description>`, e.g. `feat(router): ...` or
  `fix(dhcp): ...` (matches this repo's existing history). Standard types:
  `feat`, `fix`, plus `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `chore`, `ci` as needed. A breaking change is marked either with `!`
  right after the type/scope (e.g. `feat(router)!: ...`) or a
  `BREAKING CHANGE:` footer.

## Progress

- `cluster-router` NixOS configuration implemented under
  `nix/hosts/cluster-router`, covering: vlan-tagged interfaces, ip
  forwarding, nftables firewall, kea DHCP server for the infra vlan, a
  netboot (tftp + http) server stub for Talos images, wireguard on the WAN
  side, and a load-balancer in front of the kubernetes API.
- Host-specific values (vlan ids/cidrs, host IPs) live in
  `nix/hosts/lib.nix`. Modules under `nix/modules` only exist where they
  provide real abstraction (currently just `loadbalancer/haproxy.nix`,
  parameterized by publish address / backend nodes / port tuples); anything
  that would just forward config 1:1 is written directly in the host file.
- `flake.nix` exposes `nixosConfigurations.cluster-router`,
  `colmenaHive.cluster-router`, and
  `packages.aarch64-linux.cluster-router-sd-image`, all built from the same
  shared module list so the two deployment paths (SD-image bootstrap,
  colmena for ongoing changes) can't drift apart. See README for the
  deployment instructions.
- Wireguard is set up via `networking.wg-quick.interfaces.wg0.configFile`
  pointing at `/etc/wireguard/wg0.conf` — a plain `wg-quick`
  `[Interface]`/`[Peer]` file that is hand-created/edited directly on the
  host, not generated or tracked by Nix. sops-nix was removed entirely
  (it existed only for the wireguard private key); there are currently no
  secrets managed by this repo.
- `nix/hosts/cluster-router/hardware-configuration.nix` is a placeholder;
  needs to be replaced/verified once real hardware is imaged.
- SSH is enabled (`services.openssh`, root key-only via
  `PermitRootLogin = "prohibit-password"`) with an authorized key for root,
  so colmena can reach the host once imaged.
- `vlan-wan` has a default route (`0.0.0.0/0` via `net.vlans.wan.gateway`,
  set in `nix/hosts/lib.nix`).
- `networking.nftables.enable` is back to `true` (bring-up debugging that
  required it disabled is done). Ruleset: `vlan-infra` is fully trusted;
  `vlan-wan` accepts SSH, WireGuard, ping, forwards tcp/50000 (Talos
  apid) through to `vlan-infra` by explicit decision (the only
  `vlan-wan` -> `vlan-infra` `forward`-chain path not gated behind the
  VPN by itself), and accepts every port published via haproxy (currently
  just tcp/6443, the Kubernetes API) on the router's own `input` chain,
  since haproxy listens on the router itself — both generated from
  `services.cluster.haproxy.ports` via `wanPublishedPorts` in
  `nix/hosts/cluster-router/default.nix`, see the standing instruction
  above; `wg0` (VPN clients) can reach the router itself, `vlan-infra`,
  and the general internet via `vlan-wan`, but not `vlan-wan`'s home
  subnet (192.168.1.0/24) nor other VPN clients (192.168.3.0/24) — see
  README's flow matrix/ports table for specifics.
- First SD image built and flashed to hardware; the switch port connecting
  to cluster-router has been configured as an 802.1Q trunk carrying vlan 1
  + vlan 10. `colmena apply` has succeeded against the real host at
  192.168.1.145.
- `vlan-infra` DHCP is `dnsmasq` (`services.dnsmasq` in
  `nix/hosts/cluster-router/default.nix`), plain config now: `dhcp-range`
  (192.168.2.100-200 dynamic pool), `dhcp-option` for router/DNS,
  `dhcp-host` static reservations for the 3 node MACs observed during
  netboot bring-up (`d8:3a:dd:26:57:5e` -> cluster-master-1, confirmed;
  `d8:3a:dd:26:57:7f` -> cluster-worker-1 and `d8:3a:dd:26:57:91` ->
  cluster-worker-2, still unconfirmed guesses). Kea was tried first and
  fully removed (not just disabled) in favor of dnsmasq, which has native
  PXE support more in line with a home-lab-scale setup — see README's
  "Technical stack" section.

### Netboot (RPi4 -> Talos) — PARKED, not removed

Extensively attempted and ultimately set aside in favor of flashing Talos
directly to SD cards; revisit later. Implementation is left in place in
`nix/hosts/cluster-router/default.nix`, commented out rather than
deleted, so it's a quick re-enable: uncomment `pxe-service`/`dhcp-boot`/
`enable-tftp`/`tftp-root`/`tftp-mtu` in `services.dnsmasq.settings` and
the `systemd.tmpfiles.rules` block that populates `/var/lib/tftpboot`
from the `tftpbootFiles` derivation (RPi4 firmware + U-Boot, built from
`pkgs.raspberrypifw` + `pkgs.ubootRaspberryPi4_64bit`, `u-boot.bin`
renamed `kernel8.img`, plus a declaratively-generated
`pxelinux.cfg/default`). Talos kernel/initramfs (`talos/vmlinuz`,
`talos/initramfs.xz`, from Talos Factory, schematic ID
`ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9`
v1.14.4) are already sitting on cluster-router under
`/var/lib/tftpboot/talos/`, left there (not Nix-managed) for next time.

What was learned, in case this is picked up again:

- **Kea vs dnsmasq**: Kea's DHCP output was verified byte-correct via
  packet capture (proper `siaddr`/`file`, option 60 `vendor-class-
  identifier`, and — per `raspberrypi/rpi-eeprom`'s firmware-2711 release
  notes — a byte-correct option 43 literal string `"Raspberry Pi Boot"`,
  since the RPi4 EEPROM/bootloader does its own ad-hoc string match on
  option 43 rather than real PXE TLV sub-options), yet the RPi4 PXE
  client never progressed past DHCPDISCOVER on any of the 3 nodes.
  Switching to dnsmasq (built-in `pxe-service` directive, no hand-rolled
  option 43) did fix that specific symptom — nodes reliably reached
  `pxelinux.cfg/default` afterwards.
- **BOOT_ORDER**: `BOOT_ORDER=0xf21` is the *correct* network-first value
  — confirmed via Raspberry Pi's own `raspi-config` -> Advanced Options ->
  Boot Order producing that exact value. An earlier note in this file
  claiming `BOOT_ORDER` is parsed right-to-left (implying `0xf12` was
  needed) was wrong; trust `raspi-config`'s own output over secondary
  sources on this.
- **The real blocker — large TFTP transfers**: once past
  `pxelinux.cfg/default`, the ~19MB Talos kernel and especially the
  ~87MB initramfs were never *reliably* fetched. Symptoms varied: full
  silent restarts with zero bytes requested, explicit "timeout sending"
  log lines from dnsmasq, and — once — a full, clean success per file
  (so the chain unquestionably *can* work end-to-end). Things ruled out:
  - blksize/fragmentation: tried default (1468), `tftp-no-blocksize`
    (512), and `tftp-mtu` at 1024 and 512 — no setting eliminated the
    intermittency.
  - dnsmasq's TFTP_TRANSFER_TIME (hardcoded 120s in `src/config.h`): read
    the source — it's a per-ACK stall detector (resets on every ACK
    received, confirmed in `handle_tftp()`), not a fixed transfer-time
    budget, so "the file is just slow" doesn't explain the timeouts; a
    genuine multi-minute stall must be happening.
  - server/network health: `curl tftp://192.168.2.1/talos/vmlinuz` *from
    cluster-router itself* completes both files cleanly in seconds at
    ~5MB/s every time — the TFTP server, file content, and local network
    path are all fully exonerated. The problem is specific to the RPi4/
    U-Boot client's real link, not the server.
  - concurrency: single-node isolation tests still showed timeouts, so
    it's not purely simultaneous-transfer congestion, though dnsmasq's
    TFTP is confirmed single-process/single-threaded (`src/tftp.c`) and
    is a real bottleneck under concurrent load regardless.
  - tftp-hpa split (dnsmasq for DHCP/PXE only, tftp-hpa via `services.
    tftpd`/xinetd for file serving, for real per-transfer OS concurrency):
    made things *worse* — tftp-hpa doesn't correctly handle the RPi4
    EEPROM firmware's early-stage TFTP requests, regressing that earlier
    stage to a repeating re-request loop that never even reached
    `pxelinux.cfg`. Reverted.
- **kernel_addr_r / ramdisk_addr_r**: this U-Boot build's compiled-in
  defaults (`kernel_addr_r=0x80000`, `ramdisk_addr_r=0x2700000`, only
  ~38MB apart) leave too little room for the 87MB initramfs — when the
  19MB kernel transfer *did* succeed, the INITRD fetch was never even
  attempted (0 bytes requested, not a timeout), consistent with a
  pre-flight size check silently aborting. `uEnv.txt` does NOT fix this:
  it is not auto-loaded by this build at all (no such string/logic in the
  `u-boot.bin` binary). A `boot.scr` (built via `pkgs.ubootTools`'s
  `mkimage`, confirmed as one of this build's scanned bootmeth
  candidates via `bootmeth_script`/"boot.scr" strings in the binary) that
  set `kernel_addr_r`/`fdt_addr_r`/`ramdisk_addr_r` before `bootflow scan`
  DID get past that specific limitation once (a node progressed to
  actually requesting `talos/initramfs.xz`, further than ever before) —
  but also caused nodes to hang completely silently after fetching
  `pxelinux.cfg/default` (confirmed via `nmap -Pn` showing zero open
  ports — the node was still just U-Boot, not Talos, despite answering
  ping; Talos's own kernel would issue a distinct third DHCP cycle that
  never appeared). Reverted; this remains unsolved.
- **Diagnosing "is it U-Boot or Talos?" remotely, no console**: ping
  alone is not conclusive (U-Boot's minimal network stack answers ICMP/
  ARP too). The reliable tells: (a) a full port scan (`nmap -Pn`) — Talos
  maintenance mode has port 50000 (apid, confirmed from Talos docs; not
  configurable) open, U-Boot has nothing; (b) a third, independent DHCP
  cycle in dnsmasq's logs — Talos's kernel brings up its own networking
  distinct from the EEPROM-stage and U-Boot-stage DHCP already seen.
- MAC->hostname mapping for the 3 nodes is still only partially
  confirmed (see `dhcp-host` note above) — worth nailing down fully
  before resuming netboot work, independent of the netboot issues above.

## Not yet started

- cluster-master-1 / cluster-worker-1 / cluster-worker-2: flashing Talos
  directly to SD cards (netboot parked, see above). Each node has local
  storage (SD/USB) for `install.disk` either way, so maintenance mode is
  one-time per node, not every boot (see README's "Maintenance mode is
  one-time, not every boot" — same logic applies whether Talos arrives
  via SD flash or netboot).
- Wireguard peers (WAN side) are not configured yet.
