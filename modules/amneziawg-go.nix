{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.multivpn.services.amneziawg-go;

  peerModule = {...}: {
    options = {
      publicKey = mkOption {
        type = types.str;
        description = "Peer's public key.";
      };

      allowedIPs = mkOption {
        type = types.listOf types.str;
        example = ["10.0.0.0/24" "::/0"];
        description = "Peer's allowed IPs.";
      };

      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "vpn.example.com:51820";
        description = "Peer's endpoint.";
      };

      persistentKeepalive = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "PersistentKeepalive interval in seconds.";
      };
    };
  };

  instanceModule = {...}: {
    options = {
      privateKeyFile = mkOption {
        type = types.path;
        description = "WireGuard private key path. Generate with `wg genkey`.";
      };

      headerProtectionKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "AmneziaWG 3 header protection key path. Generate with `awg genkey`.";
      };

      listenPort = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Port to listen on.";
      };

      settings = mkOption {
        type = types.attrsOf (types.oneOf [types.str types.int]);
        default = {};
        example = {
          Jc = 4;
          S1 = 25;
          H1 = 1525082495;
        };
        description = "AmneziaWG options.";
      };

      peers = mkOption {
        type = types.listOf (types.submodule peerModule);
        default = [];
        description = "WireGuard peers.";
      };
    };
  };

  mkConfBody = iface:
    pkgs.writeText "amneziawg.conf" (concatStringsSep "\n" (
        optional (iface.listenPort != null) "ListenPort = ${toString iface.listenPort}"
        ++ mapAttrsToList (k: v: "${k} = ${toString v}") iface.settings
        ++ concatMap (peer:
          ["" "[Peer]" "PublicKey = ${peer.publicKey}" "AllowedIPs = ${concatStringsSep ", " peer.allowedIPs}"]
          ++ optional (peer.endpoint != null) "Endpoint = ${peer.endpoint}"
          ++ optional (peer.persistentKeepalive != null) "PersistentKeepalive = ${toString peer.persistentKeepalive}")
        iface.peers
      )
      + "\n");

  mkService = dev: iface: let
    confBody = mkConfBody iface;
  in {
    description = "AmneziaWG interface ${dev}.";
    wantedBy = ["multi-user.target"];
    after = ["network-pre.target"];
    before = ["network.target"];
    path = [pkgs.amneziawg-tools];
    serviceConfig = {
      Type = "forking";
      ExecStart = "${getExe pkgs.amneziawg-go} ${dev}";
      Restart = "on-failure";
      RestartSec = 5;
      DynamicUser = true;
      # Shared by all interfaces, as their UAPI sockets live in the same directory.
      User = "amneziawg";
      RuntimeDirectory = "amneziawg";
      RuntimeDirectoryPreserve = true;
      AmbientCapabilities =
        ["CAP_NET_ADMIN"]
        ++ optional (iface.listenPort != null && iface.listenPort < 1024) "CAP_NET_BIND_SERVICE";
      LoadCredential =
        ["private-key:${iface.privateKeyFile}"]
        ++ optional (iface.headerProtectionKeyFile != null) "header-protection-key:${iface.headerProtectionKeyFile}";
    };
    postStart = ''
      awg setconf ${dev} <(
        echo '[Interface]'
        printf 'PrivateKey = %s\n' "$(cat "$CREDENTIALS_DIRECTORY/private-key")"
        if [ -e "$CREDENTIALS_DIRECTORY/header-protection-key" ]; then
          printf 'HeaderProtectionKey = %s\n' "$(cat "$CREDENTIALS_DIRECTORY/header-protection-key")"
        fi
        cat ${confBody}
      )
    '';
  };
in {
  options.multivpn.services.amneziawg-go.interfaces = mkOption {
    type = types.attrsOf (types.submodule instanceModule);
    default = {};
    description = "AmneziaWG interfaces.";
  };

  config = {
    environment.systemPackages = mkIf (cfg.interfaces != {}) [pkgs.amneziawg-tools];

    systemd.services =
      mapAttrs' (dev: iface: nameValuePair "amneziawg-go-${dev}" (mkService dev iface))
      cfg.interfaces;
  };
}
