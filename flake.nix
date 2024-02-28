{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    devenv.url = "github:cachix/devenv";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

    zls-main.url = "github:zigtools/zls";
    zls-main.inputs.nixpkgs.follows = "nixpkgs";
    zls-main.inputs.zig-overlay.follows = "zig-overlay";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = {
    nixpkgs,
    zig-overlay,
    zls-main,
    devenv,
    flake-parts,
    treefmt-nix,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        devenv.flakeModule
        treefmt-nix.flakeModule
      ];

      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = {
        config,
        pkgs,
        system,
        ...
      }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              zig = zig-overlay.packages.${system}.master;
              zls = zls-main.packages.${system}.zls;
            })
          ];
        };      

        devenv.shells.default = {
          packages = with pkgs; [
            xxd
            zls
            lldb
            commitizen
            config.treefmt.build.wrapper
          ];

          languages.nix.enable = true;
          languages.zig.enable = true;
          languages.zig.package = pkgs.zig;

          pre-commit.hooks.alejandra.enable = true;
          pre-commit.hooks.commitizen.enable = true;
          pre-commit.hooks.convco.enable = true;
          pre-commit.hooks."zigtest" = {
            enable = true;
            name = "zig test";
            description = "Runs zig build test on the project.";
            entry = "${pkgs.zig}/bin/zig build test --build-file ./build.zig";
            pass_filenames = false;
          };

          difftastic.enable = true;
        };

        treefmt = {
          projectRootFile = "flake.nix";
          programs = {
            alejandra.enable = true;
            deadnix.enable = true;
          };
          settings.formatter.zigfmt = {
            command = "${pkgs.zig}/bin/zig";
            includes = ["*.zig"];
            options = [ "fmt" ];
          };
        };
      };
    };
}
