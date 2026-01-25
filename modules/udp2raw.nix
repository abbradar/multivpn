{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.multivpn.udp2raw;

  instanceModule = {...}: {
    options = {
      address = mkOption {
        type = types.str;
        example = "[::]";
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
    };
  };

  mkSystemdUnit = iface: extraOpts: {
    path = with pkgs; [getent gawk udp2raw];
    wantedBy = ["multi-user.target"];
    wants = ["network.target"];
    after = ["network.target"];
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      destination=$(getent hosts ${escapeShellArg iface.destination} | awk '{ if ($1 ~ /:/) { print "[" $1 "]" } else { print $1 }; exit }')
      if [ -z "$destination" ]; then
        echo "Failed to resolve "${escapeShellArg iface.destination}
        exit 1
      fi

      exec udp2raw \
        -l ${escapeShellArg iface.address}:${toString iface.port} \
        -r "$destination":${toString iface.destinationPort} \
        -a \
        --mtu-warn 1500 \
        --cipher-mode none \
        --auth-mode none ${concatMapStringsSep " " escapeShellArg extraOpts}
    '';
  };
in {
  options = {
    multivpn.udp2raw = {
      servers = mkOption {
        type = types.attrsOf (types.submodule [
          instanceModule
          {
            config.address = mkDefault (
              if config.networking.enableIPv6
              then "[::]"
              else "0.0.0.0"
            );
          }
        ]);
        default = {};
        description = "UDP2RAW servers.";
      };

      clients = mkOption {
        type = types.attrsOf (types.submodule [
          instanceModule
          {
            config.address = mkDefault (
              if config.networking.enableIPv6
              then "[::1]"
              else "127.0.0.1"
            );
          }
        ]);
        default = {};
        description = "UDP2RAW clients.";
      };

      interfaces = mkOption {
        type = types.listOf types.str;
        description = "Interfaces to disable GRO and LRO for; required for UDP2RAW to work correctly.";
      };
    };
  };

  config = {
    systemd.services = mkMerge [
      (mapAttrs' (name: iface:
        nameValuePair "udp2raw-server-${name}" (mkSystemdUnit iface ["-s"]
          // {
            description = "UDP2RAW server for ${name}.";
          }))
      cfg.servers)

      (mapAttrs' (name: iface:
        nameValuePair "udp2raw-client-${name}" (mkSystemdUnit iface ["-c"]
          // {
            description = "UDP2RAW client for ${name}.";
          }))
      cfg.clients)

      (mkIf (cfg.servers != {} || cfg.clients != {}) {
        udp2raw-disable-gro = {
          description = "Disable GRO and LRO for UDP2RAW and ensure they stay off.";
          wantedBy = ["multi-user.target"];
          wants = ["network.target"];
          after = ["network.target"];
          path = with pkgs; [ethtool];
          script = ''
            while true; do
              for iface in ${concatMapStringsSep " " escapeShellArg cfg.interfaces}; do
                ethtool -K "$iface" gro off lro off
                sleep 5
              done
            done
          '';
          postStop = ''
            for iface in ${concatMapStringsSep " " escapeShellArg cfg.interfaces}; do
              ethtool -K "$iface" gro on lro on
            done
          '';
        };
      })
    ];
  };
}
