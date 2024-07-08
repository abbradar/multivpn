{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn.mtprotoproxy;
  port = 8443;
in {
  options = {
    multivpn.mtprotoproxy = {
      enable = mkEnableOption "MTPROTO proxy support";

      tlsDomain = mkOption {
        type = types.str;
        default = "google.com";
        description = "TLS domain for faking.";
      };

      key = mkOption {
        type = types.str;
        description = "Authorization key.";
      };
    };
  };

  config = mkIf (config.multivpn.enable && cfg.enable) {
    networking.firewall.allowedTCPPorts = [port];

    services.mtprotoproxy = {
      enable = true;
      port = port;
      users.tg = cfg.key;
      extraConfig = {
        "TLS_ONLY" = true;
        "TLS_DOMAIN" = cfg.tlsDomain;
        "MASK" = false;
      };
    };
  };
}
