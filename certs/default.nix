{ pkgs
, lib
, ...
}:
with lib;
let
    inherit (import ../hosts.nix) nodes;
    etcdHosts = builtins.filter (n: n.etcd.enable && n.etcd.tls) nodes;
in {
  gen-certs = pkgs.callPackage ./gen-certs.nix {
    etcdHosts = builtins.map(n: {
        cn = n.name;
        altNames = lists.singleton n.address;
    }) etcdHosts;
  };
  deploy-certs = pkgs.callPackage ./deploy-certs.nix {
    inherit etcdHosts;
  };
}
