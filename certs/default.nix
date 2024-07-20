{ pkgs
, ...
}:
{
  gen-certs = pkgs.callPackage ./gen-certs.nix {};
}
