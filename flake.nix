{
  description = "omp - terminal-based coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # nixpkgs-unstable (26.11) dropped x86_64-darwin, so instantiating pkgs
      # for it throws. sources.json still tracks the Intel macOS asset, so the
      # system can be re-added here whenever nixpkgs supports it again.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
          packages = {
            omp = pkgs.callPackage ./package.nix { };
            default = pkgs.callPackage ./package.nix { };
          };
        };

      flake = {
        overlays.default = final: _prev: {
          omp = final.callPackage ./package.nix { };
        };

        homeManagerModules.default = import ./home-module.nix;
      };
    };
}
