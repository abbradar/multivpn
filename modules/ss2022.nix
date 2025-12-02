{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.ss2022;
  encryption = "2022-blake3-aes-256-gcm";
in {
  options = {
    multivpn.ss2022 = {
      enable = mkEnableOption "Shadowsocks 2022 support";

      key = mkOption {
        type = types.str;
        description = "A random Base64-encoded 32 byte value. Generate with `openssl rand -base64 32`";
      };

      port = mkOption {
        type = types.int;
        default = 8189;
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
            password = cfg.key;
            network = "tcp,udp";
          };
        }
      ];
    };

    systemd.services.vpn-credentials-ss2022 = {
      description = "Prepare the client credentials for the Shadowsocks 2022 proxy.";
      wantedBy = ["multi-user.target"];
      path = with pkgs; [jq];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "vpn-credentials";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/vpn-credentials";
      };
      script = ''
        mkdir -p ss2022
        domain=${escapeShellArg rootCfg.domain}
        port=${toString cfg.port}
        encryption=${escapeShellArg encryption}
        key=${escapeShellArg cfg.key}

        jq -n \
          --arg domain "$domain" \
          --argjson port "$port" \
          --arg encryption "$encryption" \
          --arg key "$key" \
          '{host: $domain, port: $port, encryption: $encryption, key: $key}' \
          > ss2022/credentials.json

        encoded=$(echo -n "$encryption:$key" | base64 -w0)
        echo "ss://$encoded@$domain:$port#$domain" > ss2022/link.url
      '';
    };
  };
}
