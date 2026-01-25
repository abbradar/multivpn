{
  config,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.firewall;

  addresses = import ./addresses.nix;

  vpnSetCheckedMark = bitOr vpnMark vpnCheckedMark;

  setVpnMark = "ct mark set (ct mark or ${toString cfg.fwmark}) meta mark set (meta mark or ${toString cfg.fwmark}) accept";

  commonChains = ''
    chain multivpn-filter {
      type filter; policy drop;

      ip daddr { ${concatStringsSep "," addresses.privateNetworks4} } drop
      ip6 daddr { ${concatStringsSep "," addresses.privateNetworks6} } drop

      return
    }

    chain forward {
      type filter hook forward priority filter; policy accept;

      meta mark and ${toString vpnMark} == 0 accept
      ct state {established, related} accept

      jump multivpn-filter

      # Clamp MSS to MTU.
      tcp flags syn tcp option maxseg size set rt mtu
    }

    chain output {
      type filter hook output priority filter; policy accept;

      meta mark and ${toString vpnMark} == 0 accept
      ct state {established, related} accept

      # Allow local DNS resolution.
      ip daddr 127.0.0.0/8 udp dport 53 accept
      ip daddr 127.0.0.0/8 tcp dport 53 accept
      ip6 daddr ::1/128 udp dport 53 accept
      ip6 daddr ::1/128 tcp dport 53 accept

      jump multivpn-filter
    }

    set vpn-services {
      type cgroupsv2
    }

    chain mark {
      type filter hook prerouting priority mangle; policy accept;

      ct state {established, related} meta mark set (meta mark or (ct mark and ${toString cfg.fwmark})) accept

      ${optionalString (cfg.vpnInterfaces != []) "meta iifname { ${concatStringsSep "," cfg.vpnInterfaces} } ${setVpnMark}"}
      socket cgroupv2 level 2 @vpn-services ${setVpnMark}
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
        description = "Mark for VPN connections. Only set a single bit.";
      };
    };
  };

  config = mkIf rootCfg.enable {
    # Since we ban non-local DNS resolution for security, we need a local DNS resolver.
    services.resolved.enable = mkDefault true;

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
