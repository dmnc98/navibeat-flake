{
  description = "NaviBeat (Navidrome / OpenSubsonic client) packaged for Nix from upstream's AppImage.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Upstream also ships aarch64 AppImages, but only the x86_64 build is
      # packaged (and CI-verified) here.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # NaviBeat is closed source, so an unfree-permitting pkgs is needed.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      packages = forAllSystems (system: rec {
        navibeat = (pkgsFor system).callPackage ./navibeat.nix { };
        default = navibeat;
      });

      overlays.default = final: _prev: {
        navibeat = final.callPackage ./navibeat.nix { };
      };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);
    };
}
