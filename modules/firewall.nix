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
        default = fromHexString "0x100000";
        example = literalExpression ''lib.fromHexString "0x100000"'';
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
        tables.multivpn = {
          family = "inet";
          content = let
            setVpnMark = "ct mark set (ct mark | ${toString cfg.fwmark}) meta mark set (meta mark | ${toString cfg.fwmark}) accept";
          in ''
	    chain postrouting {
	      type nat hook postrouting priority srcnat; policy accept;
	      meta mark & ${toString cfg.fwmark} == 0 accept
	      masquerade
	    }

            chain filter {
              ip daddr { ${concatStringsSep "," addresses.privateNetworks4} } drop
              ip6 daddr { ${concatStringsSep "," addresses.privateNetworks6} } drop
            }

            # chain forward {
            #   type filter hook forward priority filter; policy accept;
            #
            #   meta mark & ${toString cfg.fwmark} == 0 accept
            #   ct state { established, related } accept
            #
            #   jump filter
            #
            #   # Clamp MSS to MTU.
            #   tcp flags syn tcp option maxseg size set rt mtu
            # }

            # `meta mark set (meta mark or (ct mark and ${toString cfg.fwmark}))` doesn't work, so we use a separate check.
            chain restore-mark {
              ct mark & ${toString cfg.fwmark} != 0 meta mark set (meta mark | ${toString cfg.fwmark})
              accept
            }

            chain mark-forward {
              type filter hook prerouting priority mangle; policy accept;

              ct state { established, related } goto restore-mark
              ${optionalString (cfg.vpnInterfaces != []) "meta iifname { ${concatStringsSep "," cfg.vpnInterfaces} } ${setVpnMark}"}
            }

            chain output {
              type filter hook output priority filter; policy accept;

              meta mark and ${toString cfg.fwmark} == 0 accept
              ct state { established, related } accept

              # Allow local DNS resolution.
              ip daddr 127.0.0.0/8 udp dport 53 accept
              ip daddr 127.0.0.0/8 tcp dport 53 accept
              ip6 daddr ::1/128 udp dport 53 accept
              ip6 daddr ::1/128 tcp dport 53 accept

              jump filter
            }

            # Populated by systemd. The name is required to not contain dashes.
            set vpnservices {
              type cgroupsv2
            }

            chain mark-output {
              type route hook output priority mangle; policy accept;

              ct state { established, related } goto restore-mark
              socket cgroupv2 level 2 @vpnservices ${setVpnMark} # MULTIVPN_NOCHECK
            };
          '';
        };
        preCheckRuleset = ''
          sed '/MULTIVPN_NOCHECK/d' -i ruleset.conf
        '';
      };

      nat.enable = true;
    };
  };
}
