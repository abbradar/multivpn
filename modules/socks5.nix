{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.socks5;
  port = 1080;
in {
  options = {
    multivpn.socks5 = {
      enable = mkEnableOption "SOCKS5 support";

      user = mkOption {
        type = types.str;
        default = "anonymous";
        description = "User password.";
      };

      password = mkOption {
        type = types.str;
        description = "User password.";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    networking.firewall.allowedTCPPorts = [port];

    multivpn.services.xray = {
      enable = true;
      inbounds = [
        {
          port = port;
          protocol = "socks";
          settings = {
            auth = "password";
            accounts = [
              {
                user = cfg.user;
                password = cfg.password;
              }
            ];
            udp = true;
            ip = rootCfg.externalLocalAddress4;
          };
        }
      ];
    };
  };
}
