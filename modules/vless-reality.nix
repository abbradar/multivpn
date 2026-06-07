{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.protocols.vless-reality;

  isXhttp = cfg.transport == "xhttp";

  flow = "xtls-rprx-vision";

  sni = head cfg.serverNames;

  useLocalUpstream = cfg.destinationDomain == null;

  # XHTTP tuning
  xhttpMode = "packet-up";
  extraXhttpSettings = {
    xmux = {
      maxConcurrency = "16-32";
      maxConnections = 0;
      cMaxReuseTimes = "64-128";
      hMaxRequestTimes = "600-900";
      hMaxReusableSecs = "1800-3000";
      hKeepAlivePeriod = 0;
    };
    # https://github.com/XTLS/Xray-core/pull/5720#issuecomment-3969369574
    xPaddingObfsMode = true;
    xPaddingPlacement = "header";
  };

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
              ({
                  id = cfg.id;
                  encryption = "none";
                }
                # The Vision flow is only used with the raw TCP transport.
                // optionalAttrs (!isXhttp) {inherit flow;})
            ];
          }
        ];
        streamSettings =
          {
            network =
              if isXhttp
              then "xhttp"
              else "tcp";
            security = "reality";
            realitySettings = {
              fingerprint = "chrome";
              serverName = sni;
              shortId = "";
            };
          }
          // optionalAttrs isXhttp {
            xhttpSettings =
              {
                path = cfg.path;
                host = rootCfg.domain;
                mode = xhttpMode;
              }
              // extraXhttpSettings;
          };
        tag = "proxy";
      }
    ];
  };

  xrayClientConfigFile = pkgs.writeText "xray-client.json" (builtins.toJSON xrayClientConfig);

  linkBase = "vless://${cfg.id}@${rootCfg.domain}:443?security=reality&encryption=none&fp=chrome&sni=${sni}";
  linkTransportQuery =
    if isXhttp
    then "&type=xhttp&mode=${xhttpMode}&host=${rootCfg.domain}"
    else "&type=tcp&flow=${flow}";

  pathEnc = escapeURL cfg.path;
  extraEnc = escapeURL (builtins.toJSON extraXhttpSettings);
in {
  options = {
    multivpn.protocols.vless-reality = {
      enable = mkEnableOption "VLESS XTLS REALITY support";

      transport = mkOption {
        type = types.enum ["vision" "xhttp"];
        default = "vision";
        description = ''
          REALITY transport. `vision` is the raw-TCP + XTLS-Vision flow.
          `xhttp` also uses XMUX.
        '';
      };

      destinationDomain = mkOption {
        type = types.nullOr types.str;
        default = "www.microsoft.com";
        example = null;
        description = ''
          An address whose certificate REALITY borrows and to which we redirect the
          traffic when the handshake fails. A high-traffic site (the default) blends
          best with the SNI/CIDR whitelisting used in Russia. If `null`, forward to
          the local upstream (steal from your own domain).
        '';
      };

      serverNames = mkOption {
        type = types.listOf types.str;
        default = ["www.microsoft.com"];
        example = [
          "example.com"
          "www.example.com"
        ];
        description = ''
          Server names of the target domain (the SNIs presented to the censor).
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

      path = mkOption {
        type = types.str;
        default = "/";
        description = ''XHTTP path. Only used when `transport = "xhttp"`.'';
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    assertions = [
      {
        assertion = !rootCfg.protocols.vless.enable;
        message = "multivpn.protocols.vless-reality and multivpn.protocols.vless both bind port 443; enable only one.";
      }
    ];

    networking.firewall.allowedTCPPorts = [80 443]; # HTTP

    multivpn = {
      protocols.vless-reality.serverNames = mkIf useLocalUpstream [rootCfg.domain];

      services.xray = {
        enable = true;
        inbounds = [
          {
            port = 443;
            protocol = "vless";
            settings = {
              clients = [
                ({
                    id = cfg.id;
                  }
                  // optionalAttrs (!isXhttp) {inherit flow;})
              ];
              decryption = "none";
            };

            streamSettings =
              {
                network =
                  if isXhttp
                  then "xhttp"
                  else "tcp";
                security = "reality";
                realitySettings = {
                  dest =
                    if useLocalUpstream
                    then "127.0.0.1:8003"
                    else "${cfg.destinationDomain}:443";
                  serverNames = cfg.serverNames;
                  privateKey = cfg.privateKey;
                  shortIds = [""];
                  xver =
                    if useLocalUpstream
                    then 2
                    else 0;
                };
              }
              // optionalAttrs isXhttp {
                xhttpSettings =
                  {
                    path = cfg.path;
                    mode = "auto";
                  }
                  // obfsSettings;
              };
          }
        ];
      };

      firewall.extraVPNOutputRules = ''
        ip daddr 127.0.0.1 tcp dport { 8003 } accept
      '';
    };

    services.nginx = mkIf useLocalUpstream {
      enable = true;
      virtualHosts.${rootCfg.domain} = {
        enableACME = true;
        forceSSL = true;
        listen = [
          {
            addr = "127.0.0.1";
            port = 8003;
            ssl = true;
            http2 = true;
            proxyProtocol = true;
          }
          {
            addr = "[::]";
            port = 80;
          }
        ];
      };
    };

    systemd.services = {
      vless-reality-forward-http = mkIf (!useLocalUpstream) {
        description = "Forward HTTP traffic to the target domain.";
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,fork,reuseaddr TCP:${cfg.destinationDomain}:80";
      };

      vpn-credentials-vless-reality = {
        description = "Prepare the client credentials for the VLESS XTLS REALITY proxy.";
        wantedBy = ["multi-user.target"];
        # Use the same Xray as the service so `x25519` output format matches the sed below.
        path = [pkgs.jq config.services.xray.package pkgs.gnused];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          set -o pipefail
          mkdir -p vless-reality
          publicKey=$(xray x25519 -i ${escapeShellArg cfg.privateKey} | sed -n 's,^Password[^:]*: ,,p')

          jq --arg publicKey "$publicKey" '
            .outbounds[0].streamSettings.realitySettings.publicKey = $publicKey
          ' ${xrayClientConfigFile} > vless-reality/xray-client.json
          ${
            if isXhttp
            then ''
              echo "${linkBase}${linkTransportQuery}&path=${pathEnc}&pbk=$publicKey&sid=&extra=${extraEnc}#"${escapeShellArg rootCfg.domain} > vless-reality/link.url
            ''
            else ''
              echo "${linkBase}${linkTransportQuery}&pbk=$publicKey#"${escapeShellArg rootCfg.domain} > vless-reality/link.url
            ''
          }
        '';
      };
    };
  };
}
