{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn;
  addresses = import ./addresses.nix;
in {
  options = {
    multivpn = {
      enable = mkEnableOption "MultiVPN module";

      domain = mkOption {
        type = types.str;
        description = "Host domain name.";
      };

      vpnInterfaces = mkOption {
        type = types.listOf types.str;
        internal = true;
        default = [];
        description = "List of the VPN interfaces that submodules define.";
      };
    };
  };

  config = mkIf cfg.enable {
    networking = {
      # To ease the configuration.
      useNetworkd = true;
      nftables = {
        enable = true;
        tables = {
          "multivpn-filter4" = {
            family = "ip";
            content = ''
              chain forward {
                type filter hook forward priority 0;

                ct state {established, related} accept
                ip daddr { ${concatStringsSep "," addresses.privateNetworks4} } drop

                accept
              }
            '';
          };

          "multivpn-filter6" = {
            family = "ip6";
            content = ''
              chain forward {
                type filter hook forward priority 0;

                ct state {established, related} accept
                ip6 daddr { ${concatStringsSep "," addresses.privateNetworks6} } drop

                accept
              }
            '';
          };
        };
      };

      nat = {
        enable = true;
        internalInterfaces = cfg.vpnInterfaces;
      };
    };
  };
}
