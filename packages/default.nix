{ pkgs
, ...
}:
{
    calico-node = pkgs.callPackage ./calico-node {};
    calico-ipam-cni-plugin = pkgs.callPackage ./calico-ipam-cni-plugin.nix {};
    calico-manifests = pkgs.callPackage ./calico-manifests {};
}
