{ stdenv
, pkgs
, ...
}:
let
    inherit (stdenv) system;
in stdenv.mkDerivation {
    name = "calico-node";
    src = ./bin;
    configurePhase = ''
        mkdir -p $out/bin/
        '';

    installPhase = ''
        runHook preInstall
        install -m 0755 $src/${system}/calico-node $out/bin/calico-node
        patchelf --replace-needed libelf.so.1 libelf.so $out/bin/calico-node
        runHook postInstall
        '';

    nativeBuildInputs = with pkgs; [
        makeWrapper
            autoPatchelfHook
    ];

    buildInputs = with pkgs; [
        libelf
            libpcap
            zlib
    ];
}
