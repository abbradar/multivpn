{
  config,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.protocols.mtprotoproxy;
  port = 8443;
in {
  options = {
    multivpn.protocols.mtprotoproxy = {
      enable = mkEnableOption "MTPROTO proxy support";

      tlsDomain = mkOption {
        type = types.str;
        default = "google.com";
        description = "TLS domain for faking.";
      };

      key = mkOption {
        type = types.str;
        description = "A 32-character hexadecimal key. Generate with: `openssl rand -hex 16`.";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
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

    systemd.services = {
      mtprotoproxy = {
        bindsTo = ["nftables.service"];
        after = ["nftables.service"];
        serviceConfig.NFTSet = "cgroup:inet:multivpn:vpnservices";
      };

      vpn-credentials-mtprotoproxy = {
        description = "Prepare the client credentials for the MTPROTO proxy.";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          mkdir -p mtprotoproxy
          domain=${escapeShellArg rootCfg.domain}
          port=${toString port}
          key=${escapeShellArg cfg.key}
          suffix=$(od -A n -t x1 <<< ${escapeShellArg cfg.tlsDomain} | tr -d ' \n')
          secret="ee$key$suffix"
          cat <<< "https://t.me/proxy?server=$domain&port=$port&secret=$secret" > mtprotoproxy/link.url
        '';
      };
    };
  };
}
