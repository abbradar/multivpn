{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
with lib; let
  cfg = config.multivpn.services.udp2raw;
  mvLib = import ./lib.nix {inherit lib;};

  instanceModule = {...}: {
    options = {
      address = mkOption {
        type = mvLib.types.ipAddress;
        description = "Address to listen on.";
      };

      port = mkOption {
        type = types.int;
        description = "Port to listen on.";
      };

      destination = mkOption {
        type = types.str;
        example = "example.com";
        description = "Destination host to forward to.";
      };

      destinationPort = mkOption {
        type = types.int;
        description = "Destination port to forward to.";
      };

      key = mkOption {
        type = types.str;
        description = "Shared secret for this tunnel; must be identical on both ends. Only referenced when cipherMode or authMode is not \"none\", so it may be left unset for an unencrypted tunnel (NixOS then errors with a readable \"used but not defined\" message only if a mode does need it). Generate with `openssl rand -base64 32`.";
      };

      cipherMode = mkOption {
        type = types.enum ["aes128cbc" "aes128cfb" "xor" "none"];
        default = "aes128cbc";
        description = "udp2raw --cipher-mode; must match on both ends of this tunnel.";
      };

      authMode = mkOption {
        type = types.enum ["hmac_sha1" "md5" "crc32" "simple" "none"];
        default = "hmac_sha1";
        description = "udp2raw --auth-mode; must match on both ends of this tunnel.";
      };
    };
  };

  needsKey = iface: iface.cipherMode != "none" || iface.authMode != "none";

  group = "udp2raw";

  # Use nftables instead of udp2raw's -a option.
  serverRule = iface:
    if iface.address == "::"
    then "meta nfproto ipv6 tcp dport ${toString iface.port} drop"
    else if iface.address == "0.0.0.0"
    then "meta nfproto ipv4 tcp dport ${toString iface.port} drop"
    else "${mvLib.nftFamily iface.address} daddr ${iface.address} tcp dport ${toString iface.port} drop";

  mkSystemdUnit = iface: extraOpts: extraConfig:
    recursiveUpdate {
      path = with pkgs; [getent gawk udp2raw];
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        DynamicUser = true;
        AmbientCapabilities = ["CAP_NET_RAW"];
      };
      script = ''
        # Strip any config-supplied brackets (IPv6 literal), resolve via getent
        # ahosts (getaddrinfo — passes IP literals through, resolves hostnames,
        # and never reverse-resolves an IP the way `getent hosts` does), then
        # re-bracket an IPv6 result for udp2raw's host:port parser.
        dest=${escapeShellArg iface.destination}
        dest=''${dest#"["}
        dest=''${dest%"]"}
        destination=$(getent ahosts "$dest" | awk '{ if ($1 ~ /:/) { print "[" $1 "]" } else { print $1 }; exit }')
        if [ -z "$destination" ]; then
          echo "Failed to resolve $dest"
          exit 1
        fi

        exec udp2raw \
          -l ${escapeShellArg (mvLib.hostPort iface.address iface.port)} \
          -r "$destination":${toString iface.destinationPort} \
          --mtu-warn 1500 \
          --disable-color \
          --cipher-mode ${escapeShellArg iface.cipherMode} \
          --auth-mode ${escapeShellArg iface.authMode}${optionalString (needsKey iface) " -k ${escapeShellArg iface.key}"} \
          ${concatMapStringsSep " " escapeShellArg extraOpts}
      '';
    }
    extraConfig;
in {
  options = {
    multivpn.services.udp2raw = {
      servers = mkOption {
        type = types.attrsOf (types.submodule [
          instanceModule
          {
            # udp2raw serves a single address family, so "::" would be IPv6-only.
            options.address = mkOption {default = "0.0.0.0";};
          }
        ]);
        default = {};
        description = "UDP2RAW servers.";
      };

      clients = mkOption {
        type = types.attrsOf (types.submodule [
          instanceModule
          {
            options.address = mkOption {default = "127.0.0.1";};
          }
        ]);
        default = {};
        description = "UDP2RAW clients.";
      };

      interfaces = mkOption {
        type = types.listOf types.str;
        description = "Interfaces to disable GRO and LRO for; required for UDP2RAW to work correctly.";
      };

      connMark = mkOption {
        type = types.int;
        default = fromHexString "0x200000";
        example = literalExpression ''lib.fromHexString "0x200000"'';
        description = "Conntrack mark for UDP2RAW connections. Only set a single bit.";
      };
    };
  };

  config = {
    # No assertion for a missing key: `key` is a required option that the unit
    # only reads when a cipher/auth mode is set, so an unset key on an
    # unencrypted tunnel is fine and a needed-but-unset key trips NixOS's own
    # readable "used but not defined" error.
    assertions = optional (cfg.servers != {} || cfg.clients != {}) {
      assertion = config.networking.nftables.enable;
      message = "multivpn: UDP2RAW requires nftables for its firewall rules; set networking.nftables.enable = true.";
    };

    systemd.services = mkMerge [
      (mapAttrs' (name: iface:
        nameValuePair "udp2raw-server-${name}" (mkSystemdUnit iface ["-s"] {
          description = "UDP2RAW server for ${name}.";
        }))
      cfg.servers)

      (mapAttrs' (name: iface:
        nameValuePair "udp2raw-client-${name}" (mkSystemdUnit iface ["-c"] {
          description = "UDP2RAW client for ${name}.";
          serviceConfig.Group = group;
        }))
      cfg.clients)

      (mkIf (cfg.servers != {} || cfg.clients != {}) {
        udp2raw-disable-gro = let
          devices = map (iface: "sys-subsystem-net-devices-${utils.escapeSystemdPath iface}.device") cfg.interfaces;
        in {
          description = "Disable GRO and LRO for UDP2RAW and ensure they stay off.";
          wantedBy = ["multi-user.target"];
          bindsTo = devices;
          after = ["network-pre.target"] ++ devices;
          before = ["network.target"];
          path = with pkgs; [ethtool];
          serviceConfig = {
            DynamicUser = true;
            AmbientCapabilities = ["CAP_NET_ADMIN"];
          };
          script = ''
            while true; do
              for iface in ${concatMapStringsSep " " escapeShellArg cfg.interfaces}; do
                ethtool -K "$iface" rx-gro-hw off gro off lro off
                sleep 5
              done
            done
          '';
          postStop = ''
            for iface in ${concatMapStringsSep " " escapeShellArg cfg.interfaces}; do
              ethtool -K "$iface" rx-gro-hw on gro on lro on
            done
          '';
        };
      })
    ];

    users.groups.${group} = mkIf (cfg.clients != {}) {};

    networking.nftables = mkMerge [
      (mkIf (cfg.servers != {}) {
        tables.udp2raw = {
          family = "inet";
          content = ''
            chain server-input {
              type filter hook input priority filter; policy accept;
              ${concatMapStringsSep "\n" serverRule (attrValues cfg.servers)}
            }
          '';
        };
      })

      (mkIf (cfg.clients != {}) {
        tables.udp2raw = {
          family = "inet";
          content = let
            mark = toString cfg.connMark;
          in ''
            chain client-output {
              type filter hook output priority filter; policy accept;
              meta l4proto tcp meta skgid ${group} ct mark set ct mark | ${mark} # MULTIVPN_NOCHECK
            }

            chain client-input {
              type filter hook input priority filter; policy accept;
              meta l4proto tcp ct mark & ${mark} != 0 drop
            }
          '';
        };
        preCheckRuleset = ''
          sed '/MULTIVPN_NOCHECK/d' -i ruleset.conf
        '';
      })
    ];
  };
}
