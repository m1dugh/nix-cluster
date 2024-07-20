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
    { self
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
            certs = pkgs.callPackage ./certs { };
          in
          {
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

        raspi = import ./config/raspi;
      };

      nixosConfigurations =
        let
          pkgsFor = flake-utils.lib.eachDefaultSystemMap (system:
            let
              localPackages = self.packages.${system};
            in
            import nixpkgs {
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
            }
          );
          makeRpiConfigCustom =
              args:
              { extraModules ? []
              }:
            let
              system = "aarch64-linux";
            in
            lib.nixosSystem {
              inherit system;
              pkgs = pkgsFor.${system};

              specialArgs = args;

              modules = [
                sops-nix.nixosModules.sops
                nixos-hardware.nixosModules.raspberry-pi-4
                "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
                self.nixosModules.basic
                self.nixosModules.raspi
              ] ++ extraModules;
            };
          makeRpiConfig = args: makeRpiConfigCustom args {};
          inherit (import ./hosts.nix) masterAddress nodes;
          masterNode = builtins.head nodes;
          basicNodes = builtins.tail nodes;
        in
        lib.recursiveUpdate
        {
            "${masterNode.name}" = makeRpiConfigCustom {
                inherit masterAddress;
                nodeConfig = masterNode;
                clusterNodes = nodes;
            } {
                extraModules = [
                    ./config/master
                ];
            };
        }
        (builtins.listToAttrs (builtins.map (nodeConfig: {
            inherit (nodeConfig) name;
            value = makeRpiConfig {
                inherit masterAddress nodeConfig;
                clusterNodes = nodes;
            };
        }) basicNodes));

      formatter = flake-utils.lib.eachDefaultSystemMap
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
