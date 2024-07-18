{
  description = "A flake for k8s nixos cluster on rapsberry pis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    systems.url = "github:nix-systems/default-linux";

    sops-nix = {
        url = "github:Mic92/sops-nix";
        inputs = {
            nixpkgs-stable.follows = "nixpkgs";
        };
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs =
    { 
    self
    , nixpkgs
    , sops-nix
    , flake-utils
    , ...
    }:

    let inherit (nixpkgs) lib;
    in {
        packages = 
            flake-utils.lib.eachDefaultSystemMap (system:
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
            });
      nixosModules = {
        kubernetes = {
            imports = [
                ./modules/kubernetes
                ./modules/calico
            ];
        };
      };

      nixosConfigurations = 
      let pkgsFor = flake-utils.lib.eachDefaultSystemMap (system: 
      let localPackages = self.packages.${system};
      in import nixpkgs {
        inherit system;
        overlays = [
            (final: prev: {
                inherit (localPackages) calico-node;
            })
        ];
      });
      in {
        cluster-master-vm =
        let system = "x86_64-linux";
        in lib.nixosSystem {
            inherit system;
            pkgs = pkgsFor.${system};
            specialArgs = {
                ipAddress = "192.168.1.145";
                masterAddress = "192.168.1.145";
            };

            modules = [
                self.nixosModules.kubernetes
                sops-nix.nixosModules.sops
                ./config
            ];
        };
        cluster-master = 
        let system = "aarch64-linux";
        in lib.nixosSystem {
            inherit system;
            pkgs = pkgsFor.${system};

            modules = [
                self.nixosModules.kubernetes
                sops-nix.nixosModules.sops
                ./config
            ];
        };
      };

      formatter = flake-utils.lib.eachDefaultSystemMap
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
