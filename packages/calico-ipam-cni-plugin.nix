{ stdenv
, pkgs
,  ...
}:
let
    plg = pkgs.calico-cni-plugin;
in stdenv.mkDerivation {
    name = "calico-ipam-cni-plugin";
    src = plg;

    nativeInputs = [
        plg
    ];

    installPhase = ''
        mkdir -p $out/bin
        ln -s $src/bin/calico $out/bin/calico-ipam
    '';
}
