{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.multivpn.services.udp2raw;

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
        --cipher-mode ${escapeShellArg cfg.cipherMode} \
        --auth-mode ${escapeShellArg cfg.authMode} \
        -k ${escapeShellArg cfg.key} ${concatMapStringsSep " " escapeShellArg extraOpts}
    '';
  };
in {
  options = {
    multivpn.services.udp2raw = {
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

      key = mkOption {
        type = types.str;
        description = "Shared secret; must be identical on the server and all clients. Generate with `openssl rand -base64 32`.";
      };

      cipherMode = mkOption {
        type = types.enum ["aes128cbc" "aes128cfb" "xor" "none"];
        default = "aes128cbc";
        description = "udp2raw --cipher-mode; must match on the server and all clients.";
      };

      authMode = mkOption {
        type = types.enum ["hmac_sha1" "md5" "crc32" "simple" "none"];
        default = "hmac_sha1";
        description = "udp2raw --auth-mode; must match on the server and all clients.";
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
  };
}
