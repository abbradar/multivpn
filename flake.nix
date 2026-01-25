{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} ({...}: {
      flake.nixosModules.default.imports = [
        ./modules/common.nix
        ./modules/firewall.nix
        ./modules/udp2raw.nix
        ./modules/iodine.nix
        ./modules/mtprotoproxy.nix
        ./modules/openvpn.nix
        ./modules/wireguard.nix
        ./modules/xray.nix
        ./modules/vless.nix
        ./modules/vless-reality.nix
        ./modules/ss2022.nix
        ./modules/ss-legacy.nix
        ./modules/socks5.nix
      ];

      systems = ["x86_64-linux"];

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
    });
}
