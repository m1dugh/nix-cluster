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
  in `nix/hosts/cluster-router/default.nix` generates an accept rule per
  haproxy publish address/port automatically (see `wanPublishedPorts` in
  that file's `let` block; each entry's own `interface`/`address` decides
  which vlan and, when set, which specific address the rule is scoped
  to). This is an `input`-chain rule, not `forward`: haproxy listens on
  the router itself (whichever address a given entry binds — `vlan-infra`
  or `vlan-wan`), so this traffic terminates at the router rather than
  being forwarded through it (unlike e.g. Talos apid/tcp:50000, which
  really does forward straight to a `vlan-infra` node and so has its own
  `forward`-chain rule). A port must be explicitly excluded from
  `wanPublishedPorts` to keep it off `vlan-wan`; don't assume a
  haproxy-published port is VPN/infra-only without checking that list.
- Do not run `nix build` (or similar) against `cluster-router`'s
  configuration just to validate a change — `colmena apply` will build it
  at deploy time anyway, so a separate local build is redundant busywork.
- **After any `colmena apply` that touches `services.cluster.haproxy` /
  `nix/modules/loadbalancer/haproxy.nix` content, manually run `systemctl
  reload haproxy.service` on `cluster-router`.** Confirmed during testing:
  colmena correctly activates the new `/etc/haproxy.cfg` (the symlink
  target does change), but haproxy's systemd unit definition itself never
  changes between config edits, so NixOS's activation script does not
  restart/reload the service automatically — the old config keeps running
  (and the new one's ports, e.g. a newly added `localPort`, won't actually
  be listening) until reloaded by hand.
- Commit messages must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
  `<type>[optional scope]: <description>`, e.g. `feat(router): ...` or
  `fix(dhcp): ...` (matches this repo's existing history). Standard types:
  `feat`, `fix`, plus `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `chore`, `ci` as needed. A breaking change is marked either with `!`
  right after the type/scope (e.g. `feat(router)!: ...`) or a
  `BREAKING CHANGE:` footer.
- Amending a commit is **never** the solution to a mistake found after the
  fact — unless the user **explicitly** told you to amend. If a previous
  commit (pushed or not) turns out to be wrong, incomplete, or needs
  fixing, create a new commit with the fix rather than rewriting history.
- Everything related to what is deployed on the kubernetes cluster —
  ArgoCD `Application` manifests, the app-of-apps/bootstrap manifest, Helm
  values overrides, any plain Kubernetes manifests — must live under the
  `infrastructure/` folder. Nothing cluster-deployment-related belongs at
  the repo root or elsewhere (`bootstrap.yaml` itself lives at
  `infrastructure/bootstrap.yaml`, not the repo root, for this reason).

## ArgoCD / cluster infrastructure (app of apps)

Once the kubernetes cluster is up, all in-cluster infrastructure (beyond
what's bootstrapped manually) is managed declaratively via ArgoCD using an
"app of apps" pattern, rooted at the `infrastructure/` folder in this repo:

- **ArgoCD itself** is installed manually (e.g. `kubectl apply` of the
  upstream install manifest) into the `argocd` namespace — it cannot
  deploy itself. This is a one-time, out-of-band bootstrap step, not
  managed by this repo's manifests.
- **`infrastructure/`** is a plain Kustomize root (`kustomization.yaml`
  with a `resources:` list) at the repo root. It does not itself contain
  application workload manifests — it lists ArgoCD `Application` resources,
  one per piece of infrastructure to deploy (e.g. cert-manager, ingress
  controller, monitoring stack, etc. — added incrementally as the cluster
  grows).
- **The "app of apps"** is a single ArgoCD `Application` resource (not yet
  created) whose `spec.source` points at this git repo, path
  `infrastructure/`. ArgoCD reconciles that folder and, for every
  `Application` manifest it finds there, creates/manages the corresponding
  ArgoCD Application — which in turn deploys that piece of infrastructure.
  This is the standard "app of apps" bootstrap pattern: one parent
  Application that owns the lifecycle of all the child Applications listed
  under `infrastructure/`.
- **Bootstrapping order**: the app-of-apps Application itself is applied
  manually the first time (`kubectl apply -f infrastructure/bootstrap.yaml`),
  the same way ArgoCD itself is. It is also listed as a resource in
  `infrastructure/kustomization.yaml` (`bootstrap.yaml`), so once it's
  live and ArgoCD reconciles `infrastructure/`, it adopts/self-manages its
  own parent Application the same way `infrastructure/argocd/` does for
  ArgoCD itself.
- **`infrastructure/bootstrap.yaml`** is that app-of-apps Application:
  plain `spec.source` (single source, not `sources` — it has no Helm
  chart/values to combine, just this git repo) pointing at
  `repoURL: https://github.com/m1dugh/nix-cluster.git`,
  `targetRevision: main`, `path: infrastructure`. Auto-sync
  (`syncPolicy.automated` with `prune`/`selfHeal`) is enabled, same as the
  `argocd` Application, so once applied manually the first time, both it
  and everything under `infrastructure/` stay continuously reconciled with
  no further manual `kubectl apply` steps.
- **Settled per-app layout under `infrastructure/`** — pick exactly one of
  the following per app, in this order of preference:
  1. **No extra manifests, no (or trivial) values overriding (< 3
     overridden variables)**: a single `<app-name>.yaml` file directly
     under `infrastructure/`, containing just the ArgoCD `Application`.
     Values overrides this small are embedded inline in the Application's
     `spec.source.helm.values` (or `spec.sources[].helm.values`) rather
     than pulled from a separate file.
  2. **Values overriding with 3+ variables (and no extra manifests)**: a
     subfolder `infrastructure/<app-name>/` containing `application.yaml`
     (the ArgoCD `Application`) and `values.yaml` (the Helm values
     override file it points at). This is the threshold past which inline
     `helm.values` gets unwieldy enough to warrant a dedicated file.
  3. **Extra plain Kubernetes manifests needed (with or without values
     overriding)**: the same subfolder shape as (2),
     `infrastructure/<app-name>/`, plus an additional `kustomization.yaml`
     in that subfolder listing every extra manifest for the app. The
     app's `application.yaml` points at this subfolder (as a Kustomize
     source) rather than only at a Helm chart.
  - `infrastructure/argocd/` predates this rule and is the one deliberate
    exception: it uses the subfolder shape even though
    `values.yaml` currently holds only 2 variables
    (`configs.params.server.insecure`, `global.networkPolicy.create`),
    because it needs the `ref: values` git source (see below) to let the
    self-managed Helm chart read its own values file from this repo — a
    structural need unrelated to the variable-count threshold. New apps
    under this threshold that don't need that `ref: values` pattern should
    use case 1 (inline values) instead.
  - For a Helm-chart-based app using case 2 or 3,
    `application.yaml` uses `spec.sources` (plural, not `spec.source` —
    the two are mutually exclusive) with two entries: the upstream Helm
    chart repo, and this git repo referenced via `ref: values` so the
    chart's `helm.valueFiles` can point at
    `$values/infrastructure/<app>/values.yaml`. This lets each app pin its
    own chart version/repo independently while still sourcing its values
    override from this git repo. The git source's `targetRevision` must be
    `main` — this repo's default branch is `main` (`master` is only the
    old name, still lingering as `origin`'s stale remote-tracking `HEAD`
    locally; not the branch to target).
  - **Prefer an OCI Helm registry over a classic index-based repo
    whenever the chart publishes to both** (check with
    `helm show chart oci://<registry>/<path>/<chart> --version <v>` before
    assuming only one exists). For the Helm-chart source entry's
    `repoURL`/`chart` pair when using OCI: `repoURL` is the OCI path
    **without** the `oci://` scheme prefix and **without** the chart name
    itself (ArgoCD appends `chart` onto `repoURL` as the final path
    segment) — e.g. `repoURL: ghcr.io/nginx/charts` +
    `chart: nginx-gateway-fabric`, not `repoURL:
    oci://ghcr.io/nginx/charts` (the `oci://` prefix breaks ArgoCD's
    revision resolution, producing a 403 against the wrong path) and not
    `repoURL: ghcr.io/nginx/charts/nginx-gateway-fabric` (double-appends
    the chart name). This bit both `infrastructure/argocd/` (switched
    from the classic `https://argoproj.github.io/argo-helm` repo to
    `ghcr.io/argoproj/argo-helm` OCI) and
    `infrastructure/nginx-gateway-fabric/` when first written.
- `infrastructure/argocd/` is ArgoCD managing itself: `application.yaml`
  points at the upstream `argo-cd` Helm chart (OCI repo
  `ghcr.io/argoproj/argo-helm`) with `values.yaml` as the
  override, `targetRevision: 10.11.1` (pinned to the chart version
  actually deployed — bump deliberately, not via a wildcard, so ArgoCD
  never silently jumps chart versions on an unrelated sync), synced into
  the `argocd` namespace with
  automated sync + self-heal + prune, plus `ServerSideApply=true` in
  `syncOptions` (server-side apply, rather than client-side, for this
  Application's sync). This Application is included in
  `infrastructure/kustomization.yaml`'s `resources:`, so once the
  app-of-apps parent Application reconciles `infrastructure/`, ArgoCD
  adopts management of its own Helm deployment (which was installed
  manually as the initial bootstrap step).
- `infrastructure/argocd/values.yaml` sets `configs.params.server.insecure:
  true` — this disables TLS on `argocd-server` itself (it serves plain
  HTTP), since TLS termination is expected to be handled later by an
  upstream API gateway/ingress in front of it, not by argocd-server
  directly. Revisit this once that gateway exists and is actually fronting
  argocd-server.
- `infrastructure/argocd/values.yaml` also sets `global.networkPolicy.create:
  false` — the upstream `argo-cd` chart creates a default-deny
  `NetworkPolicy` per component otherwise (every component's own
  `networkPolicy.create` defaults to this global flag), which was blocking
  `kubectl port-forward` access to `argocd-server`. Revisit once real
  ingress/gateway access patterns are defined and explicit allow rules can
  be scoped instead of disabling the policies outright.
- `infrastructure/argocd/values.yaml`'s `extraObjects` adds an `HTTPRoute`
  (`argocd` namespace) attaching to `private-gateway`'s `http` listener
  (see the nginx-gateway-fabric section below for the hostname
  convention), hostname `argocd.int.midugh.fr`, forwarding to
  `argocd-server`'s `http`/80 port — http only for now, same as every
  other route until TLS exists.
- **ArgoCD's own initial bootstrap install must be done with `helm
  install`/`helm template`, not a raw manifest install (e.g. the upstream
  `install.yaml`).** This repo's first manual bootstrap used a raw
  manifest install, and that caused a real outage once the self-managed
  `infrastructure/argocd` Application (Helm-chart-sourced) took over:
  the chart-rendered Services select on
  `app.kubernetes.io/instance: argocd` and use named `targetPort`s (e.g.
  `repo-server` on `argocd-repo-server`), but the raw-manifest
  Deployments/StatefulSet predating Helm had neither the `instance` label
  nor named container ports — so every Service had zero matching
  endpoints the moment Helm's Services replaced the manifest-install
  ones, and `argocd-server`/`argocd-application-controller` couldn't
  reach `argocd-repo-server` at all (`ComparisonError: ... connection
  refused`), which in turn blocked ArgoCD from rendering its own Helm
  chart to self-heal — a bootstrap deadlock that required manually
  patching every affected Deployment/StatefulSet's pod template (adding
  the `instance` label and named ports) before ArgoCD could sync itself
  back to a consistent state. Bootstrapping via Helm with the same
  `values.yaml` from the start avoids this entirely, since the initial
  objects would already carry the labels/port names the chart's own
  Service selectors expect.
- **`infrastructure/gateway-api-crds.yaml`** is a required prerequisite for
  `infrastructure/nginx-gateway-fabric/`, and must sync first: the upstream
  Kubernetes **Gateway API** CRDs (`Gateway`, `GatewayClass`, `HTTPRoute`,
  etc. — group `gateway.networking.k8s.io`) are a separate project
  (`kubernetes-sigs/gateway-api`) from NGF itself, and are *not* included
  in the `nginx-gateway-fabric` chart's own `crds/` directory (that
  directory only has NGF's own CRDs, e.g. `NginxProxy`,
  `ClientSettingsPolicy` — group `gateway.nginx.org`). Without them, every
  sync of `nginx-gateway-fabric` fails outright: ArgoCD can't discover the
  `gateway.networking.k8s.io/v1` API group to create the `Gateway`/
  `GatewayClass` resources the chart templates. This is a single-file
  case-1 layout (no values/extras of its own) pointing straight at NGF's
  own pinned Kustomize source for the CRDs
  (`github.com/nginx/nginx-gateway-fabric.git`,
  `path: config/crd/gateway-api/standard`, tagged to the same
  `v2.8.0` release as the Helm chart) — the "standard" channel, not
  "experimental" (NGF docs' recommended default). Ordering is enforced via
  `argocd.argoproj.io/sync-wave` annotations: `gateway-api-crds` is
  `"-1"`, `nginx-gateway-fabric` is `"0"`, so the CRDs always land first.
- `infrastructure/nginx-gateway-fabric/` deploys NGINX Gateway Fabric
  (Kubernetes Gateway API implementation) via its upstream OCI Helm chart
  (`ghcr.io/nginx/charts`, chart `nginx-gateway-fabric`, pinned
  `targetRevision`), into the `gateway-system` namespace — see
  `infrastructure/gateway-api-crds.yaml` above for its required
  prerequisite. Like `infrastructure/argocd/`, `application.yaml` uses
  `spec.sources` with a `ref: values` git source so `helm.valueFiles` can
  point at `infrastructure/nginx-gateway-fabric/values.yaml` in this
  repo, and
  `syncOptions` includes `ServerSideApply=true` (the chart's `crds/`
  directory — one per Gateway API extension type NGF defines, e.g.
  `NginxProxy`, `ClientSettingsPolicy` — is large enough that plain
  client-side apply risks hitting the annotation-size limit).
  - One Helm release defines both gateways: the chart's `gateways:` value
    is a list, each entry rendered as its own `Gateway` resource, all
    under NGF's single `GatewayClass` (`nginx`, controller
    `gateway.nginx.org/nginx-gateway-controller`) — so one release/one
    `Application` is enough for multiple Gateways; there is no need for
    (and the chart does not cleanly support) one Helm release per Gateway.
  - `private-gateway` and `public-gateway` are each `NodePort`-typed via
    their own `NginxProxy` custom resource (NGF's way of configuring the
    Service a Gateway gets — the chart's own `templates/service.yaml` is
    unrelated, it's only the control-plane agent-grpc Service). Each
    Gateway's `spec.infrastructure.parametersRef` points at its own
    `NginxProxy` (`private-gateway-proxy-config` /
    `public-gateway-proxy-config`), and each `NginxProxy` sets
    `spec.kubernetes.service.type: NodePort` plus an explicit
    `nodePorts: [{listenerPort, port}]` mapping. These two `NginxProxy`
    objects are added via the chart's `extraObjects` values list (there is
    no dedicated values key for "extra NginxProxy per gateway").
  - Current node ports: `private-gateway` listener `http`/80 ->
    NodePort 30080; `public-gateway` listener `http`/80 -> NodePort 31080.
  - **TLS is not implemented yet.** Neither Gateway has an `https`
    listener, and the 443-NodePort slots (30443/`private-gateway`,
    31443/`public-gateway`) are left as comments in
    `infrastructure/nginx-gateway-fabric/values.yaml` rather than real
    `nodePorts` entries, since a `NodePort` with no matching Gateway
    listener port is simply ignored by NGF. Add the `https` listeners (TLS
    `mode: Terminate` + `certificateRefs`) and the corresponding
    `nodePorts` entries together, once cert-manager is installed and can
    issue the certificates those listeners would reference.
  - There is no "default gateway" concept in Gateway API (unlike
    `StorageClass`'s default annotation) — every `HTTPRoute` must name its
    `parentRefs` explicitly, so `private-gateway` vs `public-gateway` is
    purely a naming/intent convention (attach to `private-gateway` unless
    a route genuinely needs public exposure), not something enforced by
    any manifest.
  - **Hostname convention**: by default, every `HTTPRoute` attached to
    `private-gateway` is served under the `int.midugh.fr` subdomain (e.g.
    `argocd.int.midugh.fr` for the ArgoCD UI) — this is a naming
    convention applied per-`HTTPRoute` (each lists its own `hostnames:`
    explicitly; the Gateway's listener has no `hostname` restriction of
    its own), not something enforced by the Gateway/listener itself.
    `public-gateway` routes are expected to use real external domain(s)
    once defined (not yet decided). Both gateways' `http` listeners set
    `allowedRoutes.namespaces.from: All`, so an `HTTPRoute` can live in
    any namespace (e.g. `argocd`) and still attach to a gateway in
    `gateway-system` via `parentRefs[].namespace`.
  - `cluster-router` forwards to these NodePorts via haproxy: `let`-block
    `haproxyPorts` in `nix/hosts/cluster-router/default.nix` gains two
    entries binding `192.168.1.161:80` (private) and `192.168.1.162:80`
    (public) on `vlan-wan` — **the standard `80` (and later `443`)
    port externally; `remotePort` (`30080`/`31080`) is the NodePort haproxy
    forwards to on the backend, kept distinct from the shared `localPort`
    that's actually exposed.** Each is load-balanced across all 3 k8s
    nodes (NodePort services are reachable from any node) — same pattern
    as the existing `6443` (Kubernetes API) entry. Per the standing
    instruction on `wanPublishedPorts`, both are included by default (not
    excluded), so they're reachable from `vlan-wan` like every other
    haproxy-published port; see README's "Published ports" table.
  - This required extending `nix/modules/loadbalancer/haproxy.nix` twice:
    first, a per-port `interface` option (defaulting to `cfg.interface`,
    so the existing `6443` entry is unaffected) since `192.168.1.161`/
    `.162` belong to `vlan-wan`, a different interface than
    `cluster-router`'s `services.cluster.haproxy.interface = "vlan-infra"`
    — `networking.interfaces.<iface>.ipv4.addresses` is grouped by that
    per-port interface instead of assuming a single one. Second, once
    both gateways needed to share `localPort = 80` (binding the same port
    on two different `vlan-wan` addresses), `mkFrontend`'s frontend/backend
    naming had to switch from being keyed on `localPort` alone
    (`fe-80`/`be-80`, which would collide between the two entries) to
    `(address, localPort)` (e.g. `fe-192-168-1-161-80`).
  - **The nftables `input`-chain accept-rule generation for
    `wanPublishedPorts` must never hardcode `"vlan-wan"`** as the interface
    — each `haproxyPorts` entry carries its own `interface` (not always
    `vlan-wan`), so the rule-generation groups entries by their actual
    `interface` (via `lib.groupBy`) and emits an `iifname "<interface>"`
    rule per group/port. Every published port gets its own explicit rule
    regardless of interface — including `vlan-infra` entries (e.g. `6443`),
    even though `vlan-infra` is also covered by the earlier blanket
    `iifname "vlan-infra" accept` rule: a published port must not rely
    implicitly on a different, broader rule to stay reachable. This was a
    real bug caught during review: the first version of this code iterated
    `wanPublishedPorts` directly with a literal `"vlan-wan"` string baked
    into the generated rule (silently ignoring each port's real
    `interface`), and a later version dropped `vlan-infra` entries from
    this generation entirely on the (wrong) assumption the blanket rule
    made their own rule redundant.
  - **Each rule is also scoped to its specific publish `address` when one
    is set**, not just the interface: `ip daddr <address> tcp dport <port>
    accept`, rather than accepting that port from any address on the
    interface. A port with `address = null` (binds every address on the
    interface, e.g. `6443`) falls back to the wider `iifname "<interface>"
    tcp dport <port> accept`, since there's no single address to scope to.
    Live-verified: `nft list ruleset` on `cluster-router` shows
    `iifname "vlan-wan" ip daddr 192.168.1.161 tcp dport 80 accept` and
    the equivalent for `.162`, each independent of the other.
  - A related, separate bug this surfaced: `haproxyPorts`/`wanPublishedPorts`
    are a **plain Nix list literal** in this file's `let` block, not the
    actual `config.services.cluster.haproxy.ports` option value — so an
    entry with no explicit `address`/`interface` key (like `6443`) has no
    such attribute at all here, unlike the real option, where submodule
    type-checking would apply `cfg.interface`'s default. Fixed at the
    root rather than patching every field forever: a `normalizePort`
    helper (`p: { address = p.address or null; interface = p.interface or
    "vlan-infra"; } // p`) is mapped over `haproxyPorts` once, so
    individual entries can keep omitting fields they don't need — same
    ergonomics as the real option would give, without requiring the
    option system.

## Progress

- `infrastructure/metrics-server.yaml` added (case 1: single file, inline
  `helm.values`) deploying the upstream `kubernetes-sigs/metrics-server`
  Helm chart (classic index repo
  `https://kubernetes-sigs.github.io/metrics-server/` — it has no OCI
  registry, unlike `argocd`/`nginx-gateway-fabric`), pinned
  `targetRevision: 3.14.0`, into `kube-system`. Sets
  `args: [--kubelet-insecure-tls]` since Talos kubelet serving certs
  aren't signed by a CA metrics-server trusts by default; revisit if
  Talos's kubelet cert setup changes. Wired into
  `infrastructure/kustomization.yaml`.
- Kubernetes API (`6443`) moved from publishing on `192.168.2.1`
  (vlan-infra, implicitly bound there via `address = null`) to
  `192.168.1.145` (vlan-wan, the router's existing WAN address) —
  `haproxyPorts`' `6443` entry now sets `address = net.hosts.cluster-router.wan;
  interface = "vlan-wan";` explicitly. `net` (from `nix/hosts/lib.nix`)
  had to be imported earlier in the file's `let` block for this (it was
  previously only imported in a second, later `let` the haproxy-ports
  list sits outside of); the redundant later import was removed. This
  required a corresponding Talos change (cert SANs + certificate
  rotation, done manually via `talosctl` — not tracked by this repo) so
  the existing Talos API server's TLS cert actually covers
  `192.168.1.145`; not doing that first would break `talosctl`/any
  Kubernetes API client the moment DNS/clients start hitting the new
  address with a cert that doesn't list it. README's Published ports
  table updated accordingly.
- `infrastructure/kustomization.yaml` created as the app-of-apps root
  (empty `resources: []` for now — the app-of-apps Application itself is
  not yet deployed; see the section above).
- ArgoCD installed manually into the `argocd` namespace on the cluster.
- `infrastructure/argocd/application.yaml` + `values.yaml` added (ArgoCD
  self-managing itself via the upstream Helm chart, see the section
  above) and wired into `infrastructure/kustomization.yaml`.
- `infrastructure/bootstrap.yaml` added — the app-of-apps Application
  pointing at `infrastructure/`, auto-sync enabled — and listed in
  `infrastructure/kustomization.yaml` so it self-manages once live. Not
  yet applied to the cluster; `kubectl apply -f infrastructure/bootstrap.yaml`
  is the next (one-time, manual) step.
- `infrastructure/nginx-gateway-fabric/` added (`application.yaml` +
  `values.yaml`, wired into `infrastructure/kustomization.yaml`) — NGINX
  Gateway Fabric with `private-gateway`/`public-gateway` NodePort
  Gateways (30080/31080, http only — TLS not yet implemented, see the
  section above) plus matching `cluster-router` haproxy bindings on
  `192.168.1.161`/`.162`.
- `infrastructure/gateway-api-crds.yaml` added as a sync-wave-ordered
  prerequisite for `nginx-gateway-fabric` (the upstream Gateway API CRDs
  it needs, not bundled in NGF's own chart — see the section above);
  without it `nginx-gateway-fabric`'s first sync failed outright
  (`could not find the requested resource` for
  `gateway.networking.k8s.io/v1`). Also fixed both this app's and
  `infrastructure/argocd/`'s OCI Helm `repoURL` format — ArgoCD needs it
  without the `oci://` prefix and without the chart name appended (that
  combination was initially wrong on `nginx-gateway-fabric`, causing a
  403 on sync), and switched `argocd` from its classic index-based Helm
  repo to its OCI chart source since it publishes to both. Verified live:
  both `argocd` and `nginx-gateway-fabric` now sync cleanly once the
  Gateway API CRDs and the `repoURL` fixes landed.
- `infrastructure/argocd/values.yaml` gained an `HTTPRoute` (via
  `extraObjects`) exposing the ArgoCD UI at `argocd.int.midugh.fr` through
  `private-gateway`, http only — the first real route proving out the
  gateway setup end-to-end.
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
  VPN by itself), and accepts every port published via haproxy on the
  router's own `input` chain, since haproxy listens on the router itself
  — generated from `services.cluster.haproxy.ports` via
  `wanPublishedPorts` in `nix/hosts/cluster-router/default.nix`, each
  scoped to its specific publish address when one is set (see the
  standing instruction above and the nginx-gateway-fabric section's
  firewall notes for the full rule-generation details). Currently:
  `192.168.1.145:6443` (Kubernetes API) and `192.168.1.161`/
  `192.168.1.162:80` (the two gateways) — see README's Published ports
  table. `wg0` (VPN clients) can reach the router itself, `vlan-infra`,
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
- `infrastructure/vault/` added (case 2: subfolder, `application.yaml` +
  `values.yaml` — 4 overridden values crosses the inline-values
  threshold) deploying HashiCorp Vault Community Edition via its upstream
  classic index Helm repo (`https://helm.releases.hashicorp.com` — Vault
  has no OCI chart, unlike `argocd`/`nginx-gateway-fabric`), pinned
  `targetRevision: 0.34.1` (app version 2.0.4), into the `vault-system`
  namespace. Single replica standalone mode (the chart's own default —
  `server.ha.enabled` stays `false`), `server.dataStorage.size: 8Gi` and
  `server.dataStorage.storageClass: longhorn` (explicit rather than
  relying on Longhorn being the cluster's implicit default
  StorageClass), `injector.enabled: false` (no vault-agent sidecar
  injection needed for this single-instance use case). Wired into
  `infrastructure/kustomization.yaml`. Vault starts sealed and
  uninitialized after first sync — `vault operator init` /
  `vault operator unseal` against the pod is a manual, one-time step, not
  managed by this repo.
- `infrastructure/vault/values.yaml` gained an `HTTPRoute` exposing the
  Vault UI/API at `vault.int.midugh.fr` through `private-gateway`, http
  only. Unlike `argocd`/`nginx-gateway-fabric`, the Vault chart has no
  `extraObjects` values key at all — it ships its own built-in
  `server.httproute` template
  (`templates/server-httproute.yaml`) instead, so the route is configured
  via `server.httproute.enabled`/`hostnames`/`parentRefs` rather than a
  hand-written manifest; the chart fills in the backendRef (its own
  `vault` Service, port from `server.service.port`) and the default
  `PathPrefix: /` match itself.

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
