{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.iodine;

  dev = "vpn-dns";
  domain = "${cfg.subdomain}.${rootCfg.domain}";
in {
  options = {
    multivpn.iodine = {
      enable = mkEnableOption "Iodine support";

      subdomain = mkOption {
        type = types.str;
        default = "t";
        description = "Subdomain for iodine.";
      };

      ip = mkOption {
        type = types.str;
        default = "10.0.176.1";
        description = "IP address that Iodine uses.";
      };

      passwordFile = mkOption {
        type = types.path;
        description = "File containing the password. Generate with `tr -dc A-Za-z0-9 </dev/urandom | head -c 32`";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    multivpn.firewall.vpnInterfaces = [dev];

    networking.firewall = {
      allowedTCPPorts = [53]; # DNS
      allowedUDPPorts = [53];
    };

    services.iodine.server = {
      enable = true;
      domain = domain;
      ip = "${cfg.ip}/24";
      passwordFile = cfg.passwordFile;
      extraConfig = "-c -d ${escapeShellArg dev}";
    };

    systemd.services.vpn-credentials-iodine = {
      description = "Prepare the client credentials for iodine.";
      wantedBy = ["multi-user.target"];
      path = with pkgs; [jq];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "vpn-credentials";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/vpn-credentials";
      };
      script = ''
        mkdir -p iodine
        domain=${escapeShellArg domain}
        password=$(cat ${escapeShellArg cfg.passwordFile})
        jq -n \
          --arg domain "$domain" \
          --arg password "$password" \
          '{domain: $domain, password: $password}' \
          > iodine/credentials.json
      '';
    };
  };
}
