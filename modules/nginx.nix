{
  lib,
  config,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.nginx;
in {
  options = {
    multivpn.nginx = {
      enableCustomHTTPS = mkOption {
        type = types.bool;
        default = false;
        example = true;
        internal = true;
        description = ''
          Set up nginx to use custom TLS listens.
        '';
      };
    };
  };

  config = {
    services.nginx = mkIf cfg.enableCustomHTTPS {
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

    security.acme.certs.${rootCfg.domain} = mkIf cfg.enableCustomHTTPS {
      webroot = "/var/lib/acme/acme-challenge";
    };
  };
}
