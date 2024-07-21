{ pkgs
, lib
, ...
}:
with lib;
let
    inherit (import ../hosts.nix) nodes;
    etcdHosts = builtins.filter (n: n.etcd.enable && n.etcd.tls) nodes;
    workerHosts = builtins.filter (n: n.worker) nodes; 
    masterHosts = builtins.filter (n: n.master) nodes; 
in {
  gen-certs = pkgs.callPackage ./gen-certs.nix {
    inherit workerHosts masterHosts;
    etcdHosts = builtins.map(n: {
        cn = n.name;
        altNames = lists.singleton n.address;
    }) etcdHosts;
  };
  deploy-certs = pkgs.callPackage ./deploy-certs.nix {
    inherit etcdHosts workerHosts masterHosts;
  };
}
