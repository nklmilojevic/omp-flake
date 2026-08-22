# omp Nix Flake

A Nix flake that packages [omp](https://omp.sh) (oh-my-pi), a terminal-based coding agent.

## Features

- Pre-built binaries from official GitHub releases — no Rust/Bun compile
- Multi-platform support: Linux (x86_64, aarch64) and macOS (x86_64, aarch64)
- Automatic hourly updates via GitHub Actions
- Only tracks stable releases (no prereleases)
- Shell completions for bash, zsh, and fish
- Home Manager module support

## Why not the upstream flake?

`github:can1357/oh-my-pi` builds omp from source (Rust `pi-natives` plus a Bun
compile) and nobody publishes the result to a binary cache, so every version bump
costs a full local build. This flake wraps the official release artifact instead,
which is the same binary the npm and mise installers ship.

On Linux the glibc artifact is used and only its ELF interpreter is rewritten.
Nothing else may be touched: growing the dynamic section of a Bun single-file
executable (`--add-needed`, `--set-rpath`, hence also `autoPatchelfHook`) shifts
the payload appended to the binary and makes the aarch64 build SIGSEGV before
main. The binary needs nothing beyond glibc, and the wrapper sets
`OMP_NATIVE_LIBRARY_PATH` so the addons omp extracts at runtime still resolve
their dependencies in the inference workers.

## Usage

### Run directly

```bash
nix run github:nklmilojevic/omp-flake -- --version
```

### Install with nix profile

```bash
nix profile install github:nklmilojevic/omp-flake
```

### Use the overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    omp.url = "github:nklmilojevic/omp-flake";
  };

  outputs = { nixpkgs, omp, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ omp.overlays.default ];
          environment.systemPackages = [ pkgs.omp ];
        })
      ];
    };
  };
}
```

### Home Manager module

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    omp.url = "github:nklmilojevic/omp-flake";
  };

  outputs = { nixpkgs, home-manager, omp, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        omp.homeManagerModules.default
        {
          programs.omp.enable = true;
        }
      ];
    };
  };
}
```

## Version Updates

This flake is automatically updated hourly via GitHub Actions. The workflow:

1. Checks GitHub releases for new stable versions
2. Downloads binaries for all platforms
3. Computes SHA256 hashes
4. Updates `sources.json` and commits

Current version is tracked in [sources.json](./sources.json).

## Manual Update

To manually trigger an update:

1. Go to Actions > "Update omp version" > "Run workflow"
2. Or run locally: `bash update.sh`

## Development

Enter the dev shell:

```bash
cd dev && nix develop
```

## License

The Nix code in this repository is provided under the MIT license.
omp itself is licensed under the [MIT license](https://github.com/can1357/oh-my-pi/blob/main/LICENSE).
