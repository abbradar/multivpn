{
  outputs = {...}: {
    nixosModules.default.imports = [
      ./common.nix
      ./iodine.nix
      ./mtprotoproxy.nix
      ./openvpn.nix
      ./wireguard.nix
      ./xray.nix
      ./vless.nix
      ./ss2022.nix
      ./ss-legacy.nix
      ./socks5.nix
    ];
  };
}
