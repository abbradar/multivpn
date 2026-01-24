{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.multivpn.udp2raw;

  instanceModule = {
    options = {
      address = mkOption {
        type = types.str;
        description = "Address to listen on.";
      };

      port = mkOption {
        type = types.int;
        description = "Port to listen on.";
      };

      destination = mkOption {
        type = types.str;
        description = "Destination address to forward to.";
      };
    };
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
    };
  };

  config = {
    systemd.services = mkMerge [
      (mapAttrs' (name: iface:
        nameValuePair "udp2raw-server-${name}" {
          description = "UDP2RAW server for ${name}.";
          wantedBy = ["multi-user.target"];
          wants = ["network.target"];
          after = ["network.target"];
          serviceConfig = {
            Restart = "always";
            RestartSec = 5;
            # We effectively disable mtu-warn.
            ExecStart = [
              "${pkgs.udp2raw}/bin/udp2raw"
              "-s"
              "-l"
              "${iface.address}:${toString iface.port}"
              "-r"
              iface.destination
              "-a"
              "--mtu-warn"
              "1500"
              "--cipher-mode"
              "none"
              "--auth-mode"
              "none"
            ];
          };
        })
      cfg.servers)

      (mapAttrs' (name: iface:
        nameValuePair "udp2raw-client-${name}" {
          description = "UDP2RAW client for ${name}.";
          wantedBy = ["multi-user.target"];
          wants = ["network.target"];
          after = ["network.target"];
          serviceConfig = {
            Restart = "always";
            RestartSec = 5;
            ExecStart = [
              "${pkgs.udp2raw}/bin/udp2raw"
              "-c"
              "-l"
              "${iface.address}:${toString iface.port}"
              "-r"
              iface.destination
              "-a"
              "--mtu-warn"
              "1500"
              "--cipher-mode"
              "none"
              "--auth-mode"
              "none"
            ];
          };
        })
      cfg.clients)
    ];
  };
}
