# Nix Cluster

All the technical details are stored in @README.md . Any change in technical
detail **must be stored** in this file.

Current advancement of the project should be stored in the @AGENTS.md file.

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
- **`networking.nftables.enable` is currently set to `false`** — the
  firewall is intentionally disabled during initial bring-up/testing of the
  physical hardware and network wiring. There is no inbound filtering at
  all right now (SSH and everything else reachable from both vlans). This
  must be flipped back to `true` before any real/production deployment.
- First SD image built and flashed to hardware is in progress (bring-up
  phase); the switch port connecting to cluster-router has been configured
  as an 802.1Q trunk carrying vlan 1 + vlan 10.

## Not yet started

- cluster-master-1 / cluster-worker-1 / cluster-worker-2 (talos, manual
  setup via talosctl per README).
- Wireguard peers (WAN side) are not configured yet.
