{
  description = "Flake for t3code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        t3code = final.callPackage ./default.nix { };
        t3code-desktop = final.t3code.override {
          enableDesktop = true;
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          default = pkgs.t3code;
          t3code = pkgs.t3code;
          t3code-desktop = pkgs.t3code-desktop;
        });

      apps = forAllSystems (system:
        let
          cliPkg = self.packages.${system}.t3code;
          desktopPkg = self.packages.${system}.t3code-desktop;
        in
        rec {
          default = t3code;
          t3code = {
            type = "app";
            program = "${cliPkg}/bin/t3";
          };
          t3code-desktop = {
            type = "app";
            program = "${desktopPkg}/bin/t3code-desktop";
          };
        });
    };
}
