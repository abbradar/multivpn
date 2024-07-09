{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.vless;
in {
  options = {
    multivpn.vless = {
      enable = mkEnableOption "VLESS support";

      id = mkOption {
        type = types.str;
        description = "UUID for authorization. Generate with `uuidgen`";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    networking.firewall.allowedTCPPorts = [80 443]; # HTTP

    multivpn.services.xray = {
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
                xver = 1;
              }
              {
                alpn = "h2";
                dest = "8002";
                xver = 1;
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

    security.acme.certs.${rootCfg.domain}.webroot = "/var/lib/acme/acme-challenge";

    systemd.services.xray = {
      serviceConfig.LoadCredential = [
        "fullchain:/var/lib/acme/${rootCfg.domain}/fullchain.pem"
        "key:/var/lib/acme/${rootCfg.domain}/key.pem"
      ];

      preStart = ''
        cp "$CREDENTIALS_DIRECTORY/fullchain" "/tmp/fullchain.pem"
        cp "$CREDENTIALS_DIRECTORY/key" "/tmp/key.pem"
      '';
    };
  };
}
