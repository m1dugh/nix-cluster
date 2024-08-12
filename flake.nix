{
  description = "A flake for k8s nixos cluster on rapsberry pis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-old.url = "github:NixOS/nixpkgs/nixos-23.11";
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
    , nixpkgs-old
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
            localPackages = pkgs.callPackage ./packages { };
          in
          {
            inherit (certs) gen-certs build-config deploy-certs;
            inherit (localPackages)
              calico-node
              calico-ipam-cni-plugin
              ;
          });
      nixosModules = rec {
        kubernetes = {
          imports = [
            ./modules/kubernetes
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
              oldPackages = nixpkgs-old.legacyPackages.${system};
            in
            import nixpkgs {
              inherit system;
              overlays = [
                (final: prev: {
                  inherit (localPackages)
                    calico-node
                    calico-ipam-cni-plugin
                    calico-manifests
                    ;
                  inherit (oldPackages) containerd;
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
            { extraModules ? [ ]
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
          makeRpiConfig = args: makeRpiConfigCustom args { };
          inherit (import ./hosts.nix) nodes apiserver;
          masterNode = builtins.head nodes;
          basicNodes = builtins.tail nodes;
        in
        lib.recursiveUpdate
          {
            "${masterNode.name}" = makeRpiConfigCustom
              {
                inherit apiserver;
                nodeConfig = masterNode;
                clusterNodes = nodes;
              }
              {
                extraModules = [
                  ./config/master
                ];
              };
          }
          (builtins.listToAttrs (builtins.map
            (nodeConfig: {
              inherit (nodeConfig) name;
              value = makeRpiConfig {
                inherit apiserver nodeConfig;
                clusterNodes = nodes;
              };
            })
            basicNodes));

      formatter = flake-utils.lib.eachDefaultSystemMap
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
