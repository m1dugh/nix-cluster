# vi:ts=2
# vi:sw=2
{
  description = "A flake for k8s nixos cluster on rapsberry pis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default-linux";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix.url = "github:numtide/treefmt-nix";

    colmena.url = "github:zhaofengli/colmena";

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
    , colmena
    , treefmt-nix
    , ...
    }:

    let
      inherit (nixpkgs) lib;
      cluster-config = import ./cluster-config.nix {
        inherit lib;
      };
    in {
      packages =
        flake-utils.lib.eachDefaultSystemMap (system: {});

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

        colmena = {
          imports = [
            ./modules/colmena
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
          system = "aarch64-linux";
          pkgs = import nixpkgs {
            inherit system;
            overlays = lib.lists.singleton (final: prev: {
              # allow missing modules for raspi
              makeModulesClosure = x: prev.makeModulesClosure (x // {
                allowMissing = true;
              });
            });
          };
        in lib.attrsets.mapAttrs (name: cfg: lib.nixosSystem {
            inherit pkgs system;
            specialArgs = {
              inherit cluster-config;
              nodeConfig = cfg // {
                  inherit name;
              };
            };
            modules = [
                sops-nix.nixosModules.sops
                nixos-hardware.nixosModules.raspberry-pi-4
                "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ]
              ++
            (with self.outputs.nixosModules; [
              raspi
              basic
            ]) ++ lib.lists.optionals (name == cluster-config.gateway.node) [
                ./config/master
            ];
        }) cluster-config.nodes;
      devShells = flake-utils.lib.eachDefaultSystemMap (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              colmena.packages.${system}.colmena
            ];
          };
        });


      colmenaHive = colmena.lib.makeHive (
        let configs = self.nixosConfigurations;
          system = "aarch64-linux";
          pkgs = import nixpkgs {
            inherit system;
            overlays = lib.lists.singleton (final: prev: {
              # allow missing modules for raspi
              makeModulesClosure = x: prev.makeModulesClosure (x // {
                allowMissing = true;
              });
            });
          };
        in
          ({
            meta = {
              nixpkgs = pkgs;
              specialArgs = {
                colmena = true;
              };
              nodeSpecialArgs = builtins.mapAttrs (_: node: node._module.specialArgs) configs;
            };
          } // (lib.attrsets.mapAttrs (name: cfg: 
              let config = cluster-config.nodes."${name}";
            in {
              deployment.targetHost = config.address;
              imports = configs."${name}"._module.args.modules ++ [
                self.nixosModules.colmena
              ];
          }) cluster-config.nodes ))
      );

      formatter = flake-utils.lib.eachDefaultSystemMap (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treeFmtEval = (treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixpkgs-fmt.enable = true;
            programs.ruff-format.enable = true;
          });
        in
        treeFmtEval.config.build.wrapper
      );
    };
}
