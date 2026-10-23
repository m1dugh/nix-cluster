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
  `vlan-wan` only accepts SSH, WireGuard, and ping; `wg0` (VPN clients) can
  reach the router itself, `vlan-infra`, and the general internet via
  `vlan-wan`, but not `vlan-wan`'s home subnet (192.168.1.0/24) nor other
  VPN clients (192.168.3.0/24) — see README's flow matrix/ports table for
  specifics.
- First SD image built and flashed to hardware; the switch port connecting
  to cluster-router has been configured as an 802.1Q trunk carrying vlan 1
  + vlan 10. `colmena apply` has succeeded against the real host at
  192.168.1.145.

## Not yet started

- cluster-master-1 / cluster-worker-1 / cluster-worker-2 (talos, manual
  setup via talosctl per README).
- Wireguard peers (WAN side) are not configured yet.
