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

      password = mkOption {
        type = types.str;
        description = "Proxy password. Generate with `tr -dc A-Za-z0-9 </dev/urandom | head -c 32`";
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
                user = "anonymous";
                password = cfg.password;
              }
            ];
            udp = true;
            ip = rootCfg.externalLocalAddress4;
          };
        }
      ];
    };

    systemd.services.vpn-credentials-socks5 = {
      description = "Prepare the client credentials for the SOCKS5 proxy.";
      wantedBy = ["multi-user.target"];
      path = with pkgs; [jq];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "vpn-credentials";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/vpn-credentials";
      };
      script = ''
        mkdir -p socks5
        domain=${escapeShellArg rootCfg.domain}
        port=${toString port}
        password=${escapeShellArg cfg.password}
        jq -n \
          --arg domain "$domain" \
          --argjson port "$port" \
          --arg password "$password" \
          '{host: $domain, port: $port, password: $password}' \
          > socks5/credentials.json
      '';
    };
  };
}
