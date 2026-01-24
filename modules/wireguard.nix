{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.wireguard;
  # UDP2RAW adds 60 bytes of overhead.
  udp2rawMTU = 1360;

  peerModule = {...}: {
    options = {
      ip = mkOption {
        type = types.str;
        description = ''
          Peer's private IP address.
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

  instanceModule = types.submodule {
    options = {
      ip = mkOption {
        type = types.str;
        description = "Network subnet that Wireguard uses.";
      };

      port = mkOption {
        type = types.int;
        description = "Port to listen on.";
      };

      enableUDP2RAW = mkEnableOption "UDP2RAW support";

      internalPort = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Local port to listen on internally. Needed for UDP2RAW.";
      };

      amneziaWGOptions = mkOption {
        type = types.attrsOf (types.oneOf [types.str types.int]);
        default = {};
        description = "Options for AmneziaWG.";
      };

      privateKeyFile = mkOption {
        type = types.path;
        description = "WireGuard private key path. Generate with `wg genkey`";
      };

      peers = mkOption {
        type = types.listOf (types.submodule peerModule);
        default = {};
        description = "WireGuard peers.";
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
      instances = mkOption {
        type = types.attrsOf instanceModule;
        default = {};
        description = "WireGuard/AmneziaWG instances.";
      };
    };
  };

  config = mkMerge (mapAttrsToList (name: instance: let
    dev = "vpn-wg-${name}";
  in {
    multivpn.vpnInterfaces = [dev];

    networking = {
      firewall.allowedUDPPorts = mkIf (!instance.enableUDP2RAW) [instance.port];
      firewall.allowedTCPPorts = mkIf instance.enableUDP2RAW [instance.port];

      # FIXME: IPv6
      wireguard.interfaces.${dev} = {
        ips = ["${cfg.ip}/24"];
        type =
          if instance.amneziaWGOptions != {}
          then "amneziawg"
          else "wireguard";
        mtu = mkIf instance.enableUDP2RAW udp2rawMTU;
        privateKeyFile = cfg.privateKeyFile;
        listenPort =
          if instance.enableUDP2RAW
          then instance.internalPort
          else instance.port;
        peers = concatMap (mkPeer (peer: peer.ip)) cfg.peers;
        extraOptions = instance.amneziaWGOptions;
      };
    };

    multivpn.udp2raw.servers.${name} = mkIf instance.enableUDP2RAW {
      address = "0.0.0.0";
      port = instance.port;
      destination = "127.0.0.1:${toString instance.internalPort}";
    };

    systemd.services."vpn-credentials-wireguard-${name}" = {
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
        dir=wireguard-${escapeShellArg name}
        mkdir -p "$dir"
        domain=${escapeShellArg rootCfg.domain}
        port=${toString port}
        public=$(wg pubkey < ${escapeShellArg cfg.privateKeyFile})
        cat > "$dir/wg.conf" <<EOF
        [Interface]
        PrivateKey = <private key>
        Address = <ip>/32
        ${optionalString instance.enableUDP2RAW ''
          MTU = ${toString udp2rawMTU}
        ''}
        ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
            ${name} = ${toString value}
          '')
          instance.amneziaWGOptions)}

        [Peer]
        Endpoint = $domain:$port
        PublicKey = $public
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
        EOF
      '';
    };
  }) cfg.instances);
}
