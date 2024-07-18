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
      nixosModules = { };

      nixosConfigurations = { };

      formatter = flake-utils.lib.eachDefaultSystemMap
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
