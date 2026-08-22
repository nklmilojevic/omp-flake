{
  description = "Development environment for omp-flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # Nix tools
              nixfmt-rfc-style
              deadnix
              statix
              nil

              # For update script
              jq
              curl

              # Git
              git
            ];

            shellHook = ''
              echo "omp-flake dev shell"
            '';
          };
        }
      );
    };
}
