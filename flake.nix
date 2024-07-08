{
  outputs = {...}: {
    nixosModules.default.imports = [
      ./modules/common.nix
      ./modules/iodine.nix
      ./modules/mtprotoproxy.nix
      ./modules/openvpn.nix
      ./modules/wireguard.nix
      ./modules/xray.nix
      ./modules/vless.nix
      ./modules/ss2022.nix
      ./modules/s-legacy.nix
      ./modules/socks5.nix
    ];
  };
}
