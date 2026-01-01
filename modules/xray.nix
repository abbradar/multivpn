{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn.services.xray;
  addresses = import ./addresses.nix;

  inboundModule = {...}: {
    freeformType = types.attrs;

    options = {
      sniffing.enabled = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable traffic sniffing.";
      };
    };
  };
in {
  options = {
    multivpn.services.xray = {
      enable = mkEnableOption "XRay service";

      inbounds = mkOption {
        type = types.listOf (types.submodule inboundModule);
        default = [];
        description = "Inbound listeners.";
      };
    };
  };

  config = mkIf (config.multivpn.enable && cfg.enable) {
    services.xray = {
      enable = true;
      # We can't use `settings` because it's checked with XRay, which then
      # fails because it cannot find the SSL certificate.
      settingsFile = pkgs.writeText "xray.json" (builtins.toJSON {
        inbounds = cfg.inbounds;
        routing = {
          domainStrategy = "IPIfNonMatch";
          rules = [
            {
              type = "field";
              outboundTag = "block";
              ip = addresses.privateNetworks4 ++ addresses.privateNetworks6;
            }
          ];
        };
        outbounds = [
          {
            protocol = "freedom";
            tag = "direct";
          }
          {
            protocol = "blackhole";
            tag = "block";
          }
        ];

        policy = {
          levels = {
            "0" = {
              handshake = 2;
              connIdle = 120;
            };
          };
        };
      });
    };

    systemd.services.xray.serviceConfig.PrivateTmp = true;
  };
}
