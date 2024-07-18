{
  description = "A flake for k8s nixos cluster on rapsberry pis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    systems.url = "github:nix-systems/default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs =
    { nixpkgs
    , flake-utils
    , ...
    }:

    let inherit (nixpkgs) lib;
    in {
        packages = 
            (let systems = [
                "x86_64-linux"
            ];
            in flake-utils.lib.eachSystemMap systems (system:
                let pkgs = nixpkgs.legacyPackages.${system};
                in {
                    calico-node = pkgs.stdenv.mkDerivation {
                        name = "calico-node";
                        src = ./modules/calico/bin;
                        configurePhase = ''
                            mkdir -p $out/bin/
                        '';

                        installPhase = ''
                            install -m 0755 $src/${system}/calico-node $out/bin/calico-node
                        '';

                        nativeBuildInputs = with pkgs; [
                            makeWrapper
                        ];

                        postFixup = ''
                            patchelf --replace-needed libelf.so.1 libelf.so $out/bin/calico-node
                            wrapProgram $out/bin/calico-node \
                                --set LD_LIBRARY_PATH ${lib.makeLibraryPath [
                                    pkgs.libelf
                                    pkgs.libpcap
                                ]}:''$LD_LIBRARY_PATH
                        '';
                    };
            }));
      nixosModules = {
        kubernetes = {
            imports = [
                ./modules/kubernetes
            ];
        };
      };

      nixosConfigurations = { };

      formatter = flake-utils.lib.eachDefaultSystemMap
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
