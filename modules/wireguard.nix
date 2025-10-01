{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.wireguard;

  dev = "vpn-wg";
  amneziaDev = "vpn-amneziawg";
  port = 51820;
  # Hide as a GoldSrc game.
  amneziaPort = 27015;

  peerModule = {...}: {
    options = {
      ip = mkOption {
        type = types.nullOr types.str;
        description = ''
          Peer's private IP address.
        '';
      };

      amneziaIp = mkOption {
        type = types.nullOr types.str;
        description = ''
          Peer's AmneziaWG private IP address.
        '';
      };

      publicKey = mkOption {
        type = types.str;
        description = ''
          Peer's public key. Generate the private key with `wg genkey`, then get the public key with `wg pubkey`.
        '';
      };
    };
  };

  mkPeer = getIp: peer: let
    ip = getIp peer;
  in
    optional (ip != null) {
      allowedIPs = ["${ip}/32"];
      inherit (peer) publicKey;
    };
in {
  options = {
    multivpn.wireguard = {
      enable = mkEnableOption "Wireguard support";

      ip = mkOption {
        type = types.str;
        default = "10.0.174.1";
        description = "Network subnet that Wireguard uses.";
      };

      enableAmnezia = mkEnableOption "AmneziaWG support";

      amneziaIp = mkOption {
        type = types.str;
        default = "10.0.177.1";
        description = "Network subnet that AmneziaWG uses.";
      };

      privateKeyFile = mkOption {
        type = types.path;
        description = "WireGuard private key path. Generate with `wg genkey`";
      };

      peers = mkOption {
        type = types.listOf (types.submodule peerModule);
        default = {};
        description = "WireGuard/AmneziaWG peers.";
      };
    };
  };

  config = mkIf rootCfg.enable (mkMerge [
    (mkIf cfg.enable {
      multivpn.vpnInterfaces = [dev];

      networking = {
        firewall.allowedUDPPorts = [port];
        # FIXME: IPv6
        wireguard.interfaces.${dev} = {
          ips = ["${cfg.ip}/24"];
          privateKeyFile = cfg.privateKeyFile;
          listenPort = port;
          peers = concatMap (mkPeer (peer: peer.ip)) cfg.peers;
        };
      };

      systemd.services.vpn-credentials-wireguard = {
        description = "Prepare the client credentials for Wireguard.";
        wantedBy = ["multi-user.target"];
        path = with pkgs; [wireguard-tools];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          mkdir -p wireguard
          domain=${escapeShellArg rootCfg.domain}
          port=${toString port}
          public=$(wg pubkey < ${escapeShellArg cfg.privateKeyFile})
          cat > wireguard/wg.conf <<EOF
          [Interface]
          PrivateKey = <private key>
          Address = <ip>/32

          [Peer]
          Endpoint = $domain:$port
          PublicKey = $public
          AllowedIPs = 0.0.0.0/0
          PersistentKeepalive = 25
          EOF
        '';
      };
    })

    (mkIf cfg.enableAmnezia {
      multivpn.vpnInterfaces = [amneziaDev];

      networking = {
        firewall.allowedUDPPorts = [amneziaPort];
        # FIXME: IPv6
        wireguard.interfaces.${amneziaDev} = {
          type = "amneziawg";
          ips = ["${cfg.amneziaIp}/24"];
          privateKeyFile = cfg.privateKeyFile;
          listenPort = amneziaPort;
          peers = concatMap (mkPeer (peer: peer.amneziaIp)) cfg.peers;
        };
      };
    })
  ]);
}
