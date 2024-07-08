{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn.ss-legacy;
  port = 8388;
in {
  options = {
    multivpn.ss-legacy = {
      enable = mkEnableOption "Legacy Shadowsocks support";

      password = mkOption {
        type = types.str;
        description = "User password.";
      };
    };
  };

  config = mkIf (config.multivpn.enable && cfg.enable) {
    networking.firewall = {
      allowedTCPPorts = [port];
      allowedUDPPorts = [port];
    };

    multivpn.services.xray = {
      enable = true;
      inbounds = [
        {
          port = port;
          protocol = "shadowsocks";
          settings = {
            method = "aes-256-gcm";
            password = cfg.password;
            network = "tcp,udp";
          };
        }
      ];
    };
  };
}
