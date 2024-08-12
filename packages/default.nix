{ pkgs
, ...
}:
{
  calico-node = pkgs.callPackage ./calico-node { };
  calico-ipam-cni-plugin = pkgs.callPackage ./calico-ipam-cni-plugin.nix { };
}
