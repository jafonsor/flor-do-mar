{
  description = "Flor do Mar Haskell Reflex project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems =
        function:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          function (
            import nixpkgs {
              inherit system;
            }
          )
        );

      haskellPackagesFor =
        pkgs:
        pkgs.haskell.packages.ghc9103.override {
          overrides = self: _super: {
            flor-do-mar = self.callCabal2nix "flor-do-mar" ./. { };
          };
        };
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          haskellPackages = haskellPackagesFor pkgs;
        in
        {
          default = haskellPackages.flor-do-mar;
          flor-do-mar = haskellPackages.flor-do-mar;
        }
      );

      devShells = forAllSystems (
        pkgs:
        let
          haskellPackages = haskellPackagesFor pkgs;
          ghc = haskellPackages.ghcWithPackages (
            hpkgs: with hpkgs; [
              jsaddle-warp
              linear
              reflex-dom-core
              text
            ]
          );
        in
        {
          default = pkgs.mkShell {
            packages = [
              ghc
              pkgs.cabal-install
              pkgs.ghcid
              haskellPackages.haskell-language-server
              pkgs.nixfmt
            ];
          };
        }
      );
    };
}
