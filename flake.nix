{
  description = "Gimme AWS Creds";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mach-nix.url = "github:davhau/mach-nix";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    mach-nix,
    ...
  } @ inputs: let
    pythonVersion = "python310";
    packageName = "gimme-aws-creds";
  in
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        mach = mach-nix.lib.${system};
        pythonApp = mach.buildPythonApplication {
          pname = packageName;
          src = ./.;
          python = pythonVersion;
        };
        pythonAppEnv = mach.mkPython {
          python = pythonVersion;
          requirements = builtins.readFile ./requirements.txt;
        };
        pythonAppImage = let
          localPkgs =
            if pkgs.stdenv.isDarwin
            then pkgs.pkgsCross.musl64
            else pkgs;
        in
          pkgs.dockerTools.buildLayeredImage {
            name = packageName;
            contents = [localPkgs.tini localPkgs.bash pythonApp];
            config = {
              EntryPoint = ["${localPkgs.tini}/bin/tini" "--"];
              Cmd = ["${pythonApp}/bin/${packageName}"];
            };
          };
      in rec {
        packages = rec {
          # nix build '.#image'
          image = pythonAppImage;
          # nix build '.#pythonPkg'
          pythonPkg = pythonApp;
          # nix build '.#default'
          default = pythonPkg;
        };

        legacyPackages = packages.default;
        defaultPackage = packages.default;


        # nix run '.#default'
        defaultApp = flake-utils.lib.mkApp {
          drv = packages.pythonPkg;
          exePath = "/bin/${packageName}";
        };

        # nix run '.#fmt'
        apps.fmt = flake-utils.lib.mkApp {
          drv = pkgs.writeScriptBin "fmt" ''
            ${pkgs.alejandra}/bin/alejandra "$@" .
          '';
        };

        #checks.build = packages.pythonPkg;
        devShells.default = pkgs.mkShellNoCC {
          packages = [pythonAppEnv packages.pythonPkg];
          shellHook = ''
            export PYTHONPATH="${pythonAppEnv}/bin/python"
          '';
        };
      }
    );
}
