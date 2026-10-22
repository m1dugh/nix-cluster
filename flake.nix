{
  description = "Nix cluster infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "nix-systems";
    };
    nix-systems.url = "github:nix-systems/default";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      colmena,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            colmena.packages.${system}.colmena
            talosctl
            kubectl
            wireguard-tools
          ];
        };

        formatter = treefmtEval.config.build.wrapper;
      }
    )
    // (
      let
        clusterRouterModules = [
          ./nix/hosts/cluster-router
          ./nix/hosts/cluster-router/hardware-configuration.nix
        ];
      in
      {
        nixosConfigurations.cluster-router = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = clusterRouterModules;
        };

        # Boots the cluster-router config in a local QEMU VM, minus the
        # raspi4-specific hardware config and architecture. For local testing
        # only: sets a plaintext root password so you can log in at the
        # console. Run with: nixos-rebuild build-vm --flake .#test-vm
        nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./nix/hosts/cluster-router
            {
              users.users.root.initialPassword = "root";

              fileSystems."/" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };
              boot.loader.grub.device = "/dev/vda";
            }
          ];
        };

        packages.aarch64-linux.cluster-router-sd-image =
          (nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            specialArgs = { inherit inputs; };
            modules = clusterRouterModules ++ [ ./nix/hosts/cluster-router/sd-image.nix ];
          }).config.system.build.sdImage;

        colmenaHive = colmena.lib.makeHive {
          meta = {
            nixpkgs = import nixpkgs { system = "aarch64-linux"; };
            specialArgs = { inherit inputs; };
          };

          cluster-router = {
            imports = clusterRouterModules;
            deployment = {
              targetHost = "192.168.1.145";
              targetUser = "root";
            };
          };
        };
      }
    );
}
