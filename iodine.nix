{
  config,
  lib,
  ...
}:
with lib; let
  dev = "vpn-dns";

  cfg = config.multivpn.iodine;
in {
  options = {
    multivpn.iodine = {
      enable = mkEnableOption "Iodine support";

      subnet = mkOption {
        type = types.str;
        default = "10.0.176.0";
        description = "Network subnet that Iodine uses.";
      };
    };
  };

  config = mkIf (config.multivpn.enable && cfg.enable) {
    multivpn.vpnInterfaces = [dev];

    networking.firewall = {
      allowedTCPPorts = [53]; # DNS
      allowedUDPPorts = [53];
    };

    services.iodine.server = {
      enable = true;
      domain = rootCfg.domain;
      ip = "${cfg.subnet}/24";
      extraConfig = "-c -d ${escapeShellArg dev}";
    };
  };
}
