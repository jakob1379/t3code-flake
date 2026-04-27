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
        });

      apps = forAllSystems (system:
        let
          pkg = self.packages.${system}.t3code;
        in
        {
          t3code-desktop = {
            type = "app";
            program = "${pkg}/bin/t3code-desktop";
          };
        });
    };
}
