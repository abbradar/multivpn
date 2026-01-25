{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.protocols.ss-legacy;
  encryption = "aes-256-gcm";
in {
  options = {
    multivpn.protocols.ss-legacy = {
      enable = mkEnableOption "Legacy Shadowsocks support";

      password = mkOption {
        type = types.str;
        description = "Proxy password. Generate with `tr -dc A-Za-z0-9 </dev/urandom | head -c 32`";
      };

      port = mkOption {
        type = types.int;
        default = 8388;
        description = "Port to listen on.";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    networking.firewall = {
      allowedTCPPorts = [cfg.port];
      allowedUDPPorts = [cfg.port];
    };

    multivpn.services.xray = {
      enable = true;
      inbounds = [
        {
          port = cfg.port;
          protocol = "shadowsocks";
          settings = {
            method = encryption;
            password = cfg.password;
            network = "tcp,udp";
          };
        }
      ];
    };

    systemd.services.vpn-credentials-ss-legacy = {
      description = "Prepare the client credentials for the legacy Shadowsocks proxy.";
      wantedBy = ["multi-user.target"];
      path = with pkgs; [jq];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "vpn-credentials";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/vpn-credentials";
      };
      script = ''
        mkdir -p ss-legacy
        domain=${escapeShellArg rootCfg.domain}
        port=${toString cfg.port}
        encryption=${escapeShellArg encryption}
        password=${escapeShellArg cfg.password}

        jq -n \
          --arg domain "$domain" \
          --argjson port "$port" \
          --arg encryption "$encryption" \
          --arg password "$password" \
          '{host: $domain, port: $port, encryption: $encryption, password: $password}' \
          > ss-legacy/credentials.json

        encoded=$(echo -n "$encryption:$password" | base64 -w0)
        echo "ss://$encoded@$domain:$port#$domain" > ss-legacy/link.url

        outline_encoded=$(echo -n "$encryption:$password@$domain:$port" | base64 -w0)
        echo "ss://$outline_encoded#$domain" > ss-legacy/outline_link.url
      '';
    };
  };
}
