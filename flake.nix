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

    treefmt-nix.url  = "github:numtide/treefmt-nix";

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

    let inherit (nixpkgs) lib;
    in {
      packages =
        flake-utils.lib.eachDefaultSystemMap (system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            certs = pkgs.callPackage ./certs { };
          in
          {
            inherit (certs) gen-certs build-config deploy-certs;
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
          pkgsFor = flake-utils.lib.eachDefaultSystemMap (system:
            import nixpkgs {
              inherit system;
              overlays = [
                (final: prev: {
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
          inherit (import ./hosts.nix) nodes apiserver extraConfigs;
          getExtraConfig = node: if builtins.hasAttr node extraConfigs then extraConfigs."${node}" else { };
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
                colmena = false;
              }
              {
                extraModules = [
                  ./config/master
                  ./config/nfs.nix
                  (getExtraConfig masterNode.name)
                ];
              };
          }
          (builtins.listToAttrs (builtins.map
            (nodeConfig: {
              inherit (nodeConfig) name;
              value = makeRpiConfigCustom
                {
                  inherit apiserver nodeConfig;
                  clusterNodes = nodes;
                  colmena = false;
                }
                {
                  extraModules = [
                    (getExtraConfig nodeConfig.name)
                  ];
                };
            })
            basicNodes));

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



      colmenaHive = colmena.lib.makeHive
        (
          let
            configs = self.nixosConfigurations;
          in
          {
            meta = {
              description = "Raspberry pi k8s cluster";
              nixpkgs = import nixpkgs {
                system = "aarch64-linux";
              };
              nodeNixpkgs = builtins.mapAttrs (_: node: node.pkgs) configs;
              nodeSpecialArgs = builtins.mapAttrs
                (_: node: node._module.specialArgs // {
                  colmena = true;
                })
                configs;
            };
          }
          // (builtins.mapAttrs
            (_: conf:
              let
                inherit (conf._module.specialArgs) nodeConfig;
                inherit (import ./hosts.nix) deploymentConfig;
                targetHost =
                  if
                    (builtins.hasAttr "${nodeConfig.name}" deploymentConfig) && (builtins.hasAttr "address" deploymentConfig.${nodeConfig.name})
                  then
                    deploymentConfig.${nodeConfig.name}.address
                  else
                    nodeConfig.address;
              in
              ({
                deployment = {
                  # buildOnTarget = true;
                  inherit targetHost;

                  tags = builtins.filter (v: v != null) [
                    (lib.strings.optionalString (nodeConfig.etcd.enable) "etcd")
                    (lib.strings.optionalString (nodeConfig.master) "master")
                    (lib.strings.optionalString (nodeConfig.worker) "worker")
                  ];
                };

                imports = conf._module.args.modules ++ [
                  self.nixosModules.colmena
                ];

              }))
            self.nixosConfigurations)
        );


            formatter = flake-utils.lib.eachDefaultSystemMap (system: 
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    treeFmtEval = (treefmt-nix.lib.evalModule pkgs {
                        projectRootFile = "flake.nix";
                        programs.nixpkgs-fmt.enable = true;
                    });
                in treeFmtEval.config.build.wrapper
            );
    };
}
