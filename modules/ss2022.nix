{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn.ss2022;
  port = 8389;
in {
  options = {
    multivpn.ss2022 = {
      enable = mkEnableOption "Shadowsocks 2022 support";

      key = mkOption {
        type = types.str;
        description = "User key.";
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
            method = "2022-blake3-aes-256-gcm";
            password = cfg.key;
            network = "tcp,udp";
          };
        }
      ];
    };
  };
}
