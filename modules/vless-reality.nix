{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.vless-reality;

  port = 443;
  flow = "xtls-rprx-vision";

  sni = head cfg.serverNames;

  xrayClientConfig = {
    remarks = rootCfg.domain;

    inbounds = [
      {
        listen = "127.0.0.1";
        port = 1080;
        protocol = "socks";
        settings.udp = true;
      }
    ];

    outbounds = [
      {
        protocol = "vless";
        settings.vnext = [
          {
            address = rootCfg.domain;
            inherit port;
            users = [
              {
                id = cfg.id;
                encryption = "none";
                inherit flow;
              }
            ];
          }
        ];
        streamSettings = {
          network = "tcp";
          security = "reality";
          realitySettings = {
            fingerprint = "chrome";
            serverName = sni;
            shortId = "";
          };
        };
        tag = "proxy";
      }
    ];
  };

  xrayClientConfigFile = pkgs.writeText "xray-client.json" (builtins.toJSON xrayClientConfig);

  linkPrefix = "vless://${cfg.id}@${rootCfg.domain}:${toString port}?security=reality&encryption=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${sni}";
in {
  options = {
    multivpn.vless-reality = {
      enable = mkEnableOption "VLESS XTLS REALITY support";

      destinationDomain = mkOption {
        type = types.str;
        example = "example.com";
        description = ''
          An address to which we redirect the traffic when the handshake is failed.
        '';
      };

      serverNames = mkOption {
        type = types.listOf types.str;
        example = [
          "example.com"
          "www.example.com"
        ];
        description = ''
          Server names of the target domain.
        '';
      };

      id = mkOption {
        type = types.str;
        description = "UUID for authorization. Generate with `xray uuid`.";
      };

      privateKey = mkOption {
        type = types.str;
        description = "REALITY private key. Generate with `xray x25519`.";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    networking.firewall.allowedTCPPorts = [80 port]; # HTTP

    multivpn.services.xray = {
      enable = true;
      inbounds = [
        {
          port = port;
          protocol = "vless";
          settings = {
            clients = [
              {
                id = cfg.id;
                flow = "xtls-rprx-vision";
              }
            ];
            decryption = "none";
          };

          streamSettings = {
            network = "tcp";
            security = "reality";
            realitySettings = {
              dest = "${cfg.destinationDomain}:443";
              serverNames = cfg.serverNames;
              privateKey = cfg.privateKey;
              shortIds = [""];
            };
          };
        }
      ];
    };

    systemd.services = {
      vless-reality-forward-http = {
        description = "Forward HTTP traffic to the target domain.";
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,fork,reuseaddr TCP:${cfg.destinationDomain}:80";
      };

      vpn-credentials-vless-reality = {
        description = "Prepare the client credentials for the VLESS XTLS REALITY proxy.";
        wantedBy = ["multi-user.target"];
        path = with pkgs; [jq xray gnused];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          set -o pipefail
          mkdir -p vless-reality
          publicKey=$(xray x25519 -i ${escapeShellArg cfg.privateKey} | sed -n 's,^Password: ,,p')

          jq --arg publicKey "$publicKey" '
            .outbounds[0].streamSettings.realitySettings.publicKey = $publicKey
          ' ${xrayClientConfigFile} > vless-reality/xray-client.json
          echo ${escapeShellArg linkPrefix}"&pbk=$publicKey#"${escapeShellArg rootCfg.domain} > vless-reality/link.url
        '';
      };
    };
  };
}
