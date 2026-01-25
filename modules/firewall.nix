{
  config,
  lib,
  ...
}: let
  rootCfg = config.multivpn;
  cfg = rootCfg.firewall;

  addresses = import ./addresses.nix;

  vpnSetCheckedMark = bitOr vpnMark vpnCheckedMark;

  setVpnMark = "ct mark set (ct mark or ${toString cfg.fwmark}) meta mark set (meta mark or ${toString cfg.fwmark}) accept";

  commonChains = ''
    chain multivpn-filter {
      type filter;

      ip daddr { ${concatStringsSep "," addresses.privateNetworks4} } drop
      ip6 daddr { ${concatStringsSep "," addresses.privateNetworks6} } drop

      return
    }

    chain forward {
      type filter hook forward priority filter;

      ct state {established, related} accept
      meta mark and ${toString vpnMark} == ${toString vpnMark} jump multivpn-filter
      accept
    }

    chain output {
      type filter hook output priority filter;

      ct state {established, related} accept
      meta mark and ${toString vpnMark} == ${toString vpnMark} jump multivpn-filter
      accept
    }

    set vpn-services {
      type cgroupsv2
    }

    chain mark {
      type filter hook prerouting priority mangle;

      ct state {established, related} meta mark set (meta mark or (ct mark and ${toString cfg.fwmark})) accept
      ${optionalString (cfg.vpnInterfaces != []) "meta iifname { ${concatStringsSep "," cfg.vpnInterfaces} } ${setVpnMark}"}
      socket cgroupv2 level 2 @vpn-services ${setVpnMark}
      accept
    }
  '';
in {
  options = {
    multivpn.firewall = {
      vpnInterfaces = mkOption {
        type = types.listOf types.str;
        internal = true;
        default = [];
        description = "List of the VPN interfaces that submodules define.";
      };

      fwmark = mkOption {
        type = types.int;
        default = lib.fromHexString "0x100000";
        literalExample = ''lib.fromHexString "0x100000"'';
        description = "Mark for VPN connections.";
      };
    };
  };

  config = mkIf rootCfg.enable {
    networking = {
      nftables = {
        # To ease the configuration.
        enable = true;
        tables = {
          "multivpn-filter" = {
            family = "inet";
            content = ''
              chain multivpn-filter {
                type filter;

                ip daddr { ${concatStringsSep "," addresses.privateNetworks4} } drop
                ip6 daddr { ${concatStringsSep "," addresses.privateNetworks6} } drop

                return
              }

              chain forward {
                type filter hook forward priority filter;

                ct state {established, related} accept
                meta mark and ${toString vpnMark} == ${toString vpnMark} jump multivpn-filter
                accept
              }

              chain output {
                type filter hook output priority filter;

                ct state {established, related} accept
                meta mark and ${toString vpnMark} == ${toString vpnMark} jump multivpn-filter
                accept
              }

              # Populated by systemd.
              set vpn-services {
                type cgroupsv2
              }

              chain mark {
                type filter hook prerouting priority mangle;

                ct state {established, related} meta mark set (meta mark or (ct mark and ${toString cfg.fwmark})) accept
                ${optionalString (cfg.vpnInterfaces != []) "meta iifname { ${concatStringsSep "," cfg.vpnInterfaces} } ${setVpnMark}"}
                socket cgroupv2 level 2 @vpn-services ${setVpnMark}
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
