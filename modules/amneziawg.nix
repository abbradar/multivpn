{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.multivpn.services.amneziawg;

  peerModule = {...}: {
    options = {
      publicKey = mkOption {
        type = types.str;
        description = "Peer's public key.";
      };

      allowedIPs = mkOption {
        type = types.listOf types.str;
        example = ["10.0.0.0/24" "::/0"];
        description = "Allowed IPs for this peer (wg crypto routing only; kernel routes are the caller's job).";
      };

      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "vpn.example.com:51820";
        description = "Peer's endpoint host:port. Omit for peers that only connect inbound.";
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

      listenPort = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "UDP port to listen on. Omit for client interfaces.";
      };

      settings = mkOption {
        type = types.attrsOf (types.oneOf [types.str types.int]);
        default = {};
        example = {
          Jc = 4;
          S1 = 25;
          H1 = 1525082495;
        };
        description = "AmneziaWG obfuscation options (Jc, Jmin, Jmax, S1-S4, H1-H4, I1-I5, ...). Must match on both ends.";
      };

      peers = mkOption {
        type = types.listOf (types.submodule peerModule);
        default = [];
        description = "WireGuard peers.";
      };
    };
  };

  # Non-secret wg config; PrivateKey is prepended at runtime from
  # privateKeyFile. Address/MTU/routes are intentionally not set here (awg
  # rejects them, and routing differs per interface) — do those with
  # systemd-networkd in the caller.
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
    confPath = "/run/amneziawg-${dev}/${dev}.conf";
  in {
    description = "AmneziaWG (userspace) interface ${dev}.";
    wantedBy = ["multi-user.target"];
    after = ["network-pre.target"];
    wants = ["network.target"];
    before = ["network.target"];
    path = [pkgs.amneziawg-tools];
    serviceConfig = {
      # amneziawg-go daemonizes only after the TUN device and UAPI socket are
      # ready, so once the parent has forked the interface can be configured.
      Type = "forking";
      ExecStart = "${getExe pkgs.amneziawg-go} ${dev}";
      Restart = "on-failure";
      RestartSec = 5;
      RuntimeDirectory = "amneziawg-${dev}";
      RuntimeDirectoryMode = "0700";
    };
    # Apply the wg-level crypto config (private key, peers, AmneziaWG options).
    postStart = ''
      {
        echo '[Interface]'
        printf 'PrivateKey = %s\n' "$(cat ${escapeShellArg iface.privateKeyFile})"
        cat ${confBody}
      } > ${escapeShellArg confPath}
      awg setconf ${dev} ${escapeShellArg confPath}
    '';
  };
in {
  options.multivpn.services.amneziawg.interfaces = mkOption {
    type = types.attrsOf (types.submodule instanceModule);
    default = {};
    description = ''
      AmneziaWG interfaces run via the amneziawg-go userspace daemon. Each entry
      creates the interface (named by its attribute key) and applies the wg-level
      crypto with `awg setconf`; assign addresses/MTU/routes yourself with
      systemd-networkd.
    '';
  };

  config = {
    assertions = [
      {
        assertion = cfg.interfaces != {} -> config.systemd.network.enable;
        message = "multivpn: AmneziaWG interfaces require systemd-networkd; set networking.useNetworkd = true.";
      }
    ];

    systemd.services =
      mapAttrs' (dev: iface: nameValuePair "amneziawg-${dev}" (mkService dev iface))
      cfg.interfaces;
  };
}
