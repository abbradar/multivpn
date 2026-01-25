{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.protocols.vless;

  flow = "xtls-rprx-vision";

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
            port = 443;
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
          security = "tls";
          tlsSettings.fingerprint = "chrome";
        };
        tag = "proxy";
      }
    ];
  };

  xrayClientConfigFile = pkgs.writeText "xray-client.json" (builtins.toJSON xrayClientConfig);

  link = "vless://${cfg.id}@${rootCfg.domain}:443?security=tls&encryption=none&fp=chrome&type=tcp&flow=xtls-rprx-vision#${rootCfg.domain}";
in {
  options = {
    multivpn.protocols.vless = {
      enable = mkEnableOption "VLESS XTLS support";

      id = mkOption {
        type = types.str;
        description = "UUID for authorization. Generate with `uuidgen`";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    networking.firewall.allowedTCPPorts = [80 443]; # HTTP

    multivpn = {
      services.xray = {
        enable = true;
        inbounds = [
          {
            port = 443;
            protocol = "vless";
            settings = {
              clients = [
                {
                  id = cfg.id;
                  flow = "xtls-rprx-vision";
                }
              ];
              decryption = "none";
              fallbacks = [
                {
                  dest = "8001";
                  xver = 2;
                }
                {
                  alpn = "h2";
                  dest = "8002";
                  xver = 2;
                }
              ];
            };

            streamSettings = {
              network = "tcp";
              security = "tls";
              tlsSettings = {
                rejectUnknownSni = true;
                minVersion = "1.2";
                certificates = [
                  {
                    ocspStapling = 3600;
                    certificateFile = "/tmp/fullchain.pem"; # Paths from the NixOS module
                    keyFile = "/tmp/key.pem";
                  }
                ];
              };
            };
          }
        ];
      };

      firewall.extraVPNOutputRules = ''
        ip daddr 127.0.0.1 tcp dport { 8001, 8002 } accept
      '';
    };

    services.nginx = {
      enable = true;
      virtualHosts.${rootCfg.domain} = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 8001;
            proxyProtocol = true;
          }
          {
            addr = "127.0.0.1";
            port = 8002;
            proxyProtocol = true;
            extraParameters = ["http2"];
          }
        ];
      };
      # Workaround for the weird proxy SSL configuration.
      appendHttpConfig = ''
        server {
          listen 80;

          server_name ${rootCfg.domain};

          location / {
            return 301 https://$host$request_uri;
          }

          location ^~ /.well-known/acme-challenge/ {
            root /var/lib/acme/acme-challenge;
          }
        }
      '';
    };

    security.acme.certs.${rootCfg.domain} = {
      reloadServices = ["xray.service"];
      webroot = "/var/lib/acme/acme-challenge";
    };

    systemd.services = {
      xray = {
        serviceConfig.LoadCredential = [
          "fullchain:/var/lib/acme/${rootCfg.domain}/fullchain.pem"
          "key:/var/lib/acme/${rootCfg.domain}/key.pem"
        ];

        preStart = ''
          cp "$CREDENTIALS_DIRECTORY/fullchain" "/tmp/fullchain.pem"
          cp "$CREDENTIALS_DIRECTORY/key" "/tmp/key.pem"
        '';
      };

      vpn-credentials-vless = {
        description = "Prepare the client credentials for the VLESS XTLS proxy.";
        wantedBy = ["multi-user.target"];
        path = with pkgs; [jq];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          mkdir -p vless

          # Pretty-print.
          jq . ${xrayClientConfigFile} > vless/xray-client.json
          echo ${escapeShellArg link} > vless/link.url
        '';
      };
    };
  };
}
