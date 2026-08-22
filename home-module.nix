{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.omp;
in
{
  options.programs.omp = {
    enable = lib.mkEnableOption "omp - terminal-based coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The omp package to use.";
    };

    enableBinSymlink = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.isLinux;
      description = ''
        Whether to create a symlink at ~/.local/bin/omp.
        Enabled by default on Linux to ensure the binary is in a standard location.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file.".local/bin/omp" = lib.mkIf cfg.enableBinSymlink {
      source = "${cfg.package}/bin/omp";
    };
  };
}
