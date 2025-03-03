{
  description = "PyF";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/haskell-updates";

  # Broken: see https://github.com/NixOS/nix/issues/5621
  #nixConfig.allow-import-from-derivation = true;
  nixConfig.extra-substituters = [ "https://guibou.cachix.org" ];
  nixConfig.extra-trusted-public-keys =
    [ "guibou.cachix.org-1:GcGQvWEyTx8t0KfQac05E1mrlPNHqs5fGMExiN9/pbM=" ];

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in with pkgs; rec {
        inherit pkgs;
        # Explicit list of used files. Else there is always too much and
        # cache is invalidated.
        sources = lib.sourceByRegex ./. [
          "PyF.cabal$"
          ".*.hs$"
          ".*.md$"
          ".*.golden$"
          "src"
          "app"
          "src/PyF"
          "src/PyF/Internal"
          "test"
          "test/golden"
          "test/golden96"
          "LICENSE"
        ];

        pyfBuilder = hPkgs:
          let
            shell = pkg.env.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs
                ++ [ cabal-install python3 ];
            });

            # Shell with haskell language server
            shell_hls = shell.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs
                ++ [ hPkgs.haskell-language-server ];
            });

            pkg = (haskell.lib.buildFromSdist
              (hPkgs.callCabal2nix "PyF" sources { })).overrideAttrs
              (oldAttrs: {
                buildInputs = oldAttrs.buildInputs;
                passthru = oldAttrs.passthru // { inherit shell shell_hls; };
              });
            # Add the GHC version in the package name
          in pkg.overrideAttrs (old: { name = "PyF-ghc${hPkgs.ghc.version}"; });

        packages = rec {
          pyf_86 = (pyfBuilder (haskell.packages.ghc865Binary.override {
            overrides = self: super: with haskell.lib; { };
          })).overrideAttrs (old: {
            passthru.shell = old.passthru.shell.overrideAttrs (old: {
              # for some reasons, ncurses is not part of the dependencies of ghc...
              buildInputs = old.buildInputs ++ [ pkgs.ncurses ];
            });
          });

          pyf_88 = pyfBuilder (haskell.packages.ghc88.override {
            overrides = self: super: with haskell.lib; { };
          });

          pyf_810 = pyfBuilder (haskell.packages.ghc810.override {
            overrides = self: super: with haskell.lib; { };
          });

          pyf_90 = pyfBuilder (haskell.packages.ghc90.override {
            overrides = self: super: with haskell.lib; { };
          });

          pyf_92 = pyfBuilder (haskell.packages.ghc92.override {
            overrides = self: super: with haskell.lib; rec { };
          });

          # The current version for debug
          pyf_current = pyfBuilder (haskellPackages.override {
            overrides = self: super: with haskell.lib; rec { };
          });

          # GHC 9.4
          pyf_94 = pyfBuilder ((haskell.packages.ghc94.override {
            overrides = self: super:
              with haskell.lib; {
              };
          }));

          pyf_96 = pyfBuilder (haskell.packages.ghc96.override {
            overrides = self: super: with haskell.lib; rec {
            };
          });

          pyf_98 = pyfBuilder ((haskell.packages.ghcHEAD.override {
            overrides = self: super:
              with haskell.lib; {
                # Bump hspec (and dependencies)
                hspec-core = super.callHackage "hspec-core" "2.11.4" {};
                hspec-meta = super.callHackage "hspec-meta" "2.11.4" {};
                hspec = super.callHackage "hspec" "2.11.4" {};
                hspec-discover = super.callHackage "hspec-discover" "2.11.4" {};
                hspec-expectations = super.callHackage "hspec-expectations" "0.8.4" {};
                # Disabling tests breaks the loop with hspec
                base-orphans = dontCheck super.base-orphans;

              };
          }));

          pyf_all = linkFarmFromDrvs "all_pyf" [
            pyf_86
            pyf_88
            pyf_810
            pyf_90
            pyf_92
            pyf_94
            pyf_96
            pyf_98
          ];

          # Only the current build is built with python3 support
          # (i.e. extended tests)
          pyf = haskell.lib.enableCabalFlag (pyf_current.overrideAttrs
            (old: { buildInputs = old.buildInputs ++ [ python3 ]; }))
            "python_test";
        };

        apps = {
          run-ormolu = {
            type = "app";
            program = "${writeScript "pyf-ormolu" ''
              ${ormolu}/bin/ormolu --mode inplace $(git ls-files | grep '\.hs$')
              exit 0
            ''}";
          };
        };

        defaultPackage = packages.pyf;
        devShell = packages.pyf.shell_hls;
        devShells = (builtins.mapAttrs (name: value: value.shell) packages) // {
          treesitter = pkgs.mkShell { buildInputs = [ pkgs.tree-sitter pkgs.nodejs ]; };
        };
      });
}
