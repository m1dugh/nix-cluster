{
  description = "A flake for k8s nixos cluster on rapsberry pis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    systems.url = "github:nix-systems/default-linux";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    sops-nix = {
        url = "github:Mic92/sops-nix";
        inputs = {
            nixpkgs-stable.follows = "nixpkgs";
            nixpkgs.follows = "nixpkgs";
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
    , nixos-hardware
    , ...
    }:

    let inherit (nixpkgs) lib;
    in {
        packages = 
            flake-utils.lib.eachDefaultSystemMap (system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    certs = pkgs.callPackage ./certs {};
                in {
                    inherit (certs) gen-certs deploy-certs;
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
      nixosModules = rec {
        kubernetes = {
            imports = [
                ./modules/kubernetes
                ./modules/calico
            ];
        };
        gateway = {
            imports = [
                ./modules/gateway
            ];
        };

        basic = {
            imports = [
                kubernetes
                gateway
                ./config
            ];
        };

        master = {
            imports = [
                basic
                ./config/master
            ];
        };

        worker = {
            imports = [
                basic
                ./config/worker
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
                # Required for building raspi kernel
                makeModulesClosure = x: prev.makeModulesClosure (x // {
                    allowMissing = true;
                });
            })
        ];
      });
      in 
      let makeRpiWorkerNodeConfig = {
        ipAddress,
        hostName
      }: 
      let system = "aarch64-linux"; 
      in lib.nixosSystem {
            inherit system;
            pkgs = pkgsFor.${system};

            specialArgs = {
                inherit ipAddress hostName;
                masterAddress = "192.168.1.145";
                masterAPIServerPort = 6443;
                masterHostName = "cluster-master";
            };

            modules = [
                self.nixosModules.worker
                sops-nix.nixosModules.sops
                nixos-hardware.nixosModules.raspberry-pi-4
                "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ];
        };
      in {
        cluster-master-vm =
        let system = "x86_64-linux";
        in lib.nixosSystem {
            inherit system;
            pkgs = pkgsFor.${system};
            specialArgs = {
                ipAddress = "192.168.1.145";
                masterAddress = "192.168.1.145";
                masterAPIServerPort = 6443;
                hostName = "cluster-master";
            };


            modules = [
                self.nixosModules.master
                sops-nix.nixosModules.sops
                {
                    users.users.root.password = "toor";
                }
            ];
        };

        cluster-master = 
        let system = "aarch64-linux";
        in lib.nixosSystem {
            inherit system;
            pkgs = pkgsFor.${system};

            specialArgs = {
                ipAddress = "192.168.1.145";
                masterAddress = "192.168.1.145";
                masterAPIServerPort = 6443;
                hostName = "cluster-master";
            };

            modules = [
                self.nixosModules.master
                sops-nix.nixosModules.sops
                nixos-hardware.nixosModules.raspberry-pi-4
                "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ];
        };

        cluster-node-1 = makeRpiWorkerNodeConfig {
            ipAddress = "192.168.1.146";
            hostName = "cluster-node-1";
        };

        cluster-node-2 = makeRpiWorkerNodeConfig {
            ipAddress = "192.168.1.147";
            hostName = "cluster-node-2";
        };

        cluster-node-3 = makeRpiWorkerNodeConfig {
            ipAddress = "192.168.1.148";
            hostName = "cluster-node-3";
        };
      };

      formatter = flake-utils.lib.eachDefaultSystemMap
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
