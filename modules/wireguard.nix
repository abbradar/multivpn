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
      ipv4 = mkOption {
        type = types.nullOr types.str;
        description = ''
          Peer's private IPv4 address.
        '';
      };

      ipv6 = mkOption {
        type = types.nullOr types.str;
        description = ''
          Peer's private IPv6 address.
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
      ipv4 = mkOption {
        type = types.nullOr types.str;
        example = "10.0.174.1";
        description = "Network address and a /24 subnet that Wireguard uses.";
      };

      ipv6 = mkOption {
        type = types.nullOr types.str;
        example = "fd80:f700:3bb2::1";
        description = "Network address and a /64 subnet that Wireguard uses.";
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
      assertions =
        [
          {
            assertion = instance.ipv4 != null || instance.ipv6 != null;
            message = "At least one IP address must be set for Wireguard instance ${name}.";
          }
        ]
        ++ concatMap (peer: [
          {
            assertion = peer.ipv4 != null -> instance.ipv4 != null;
            message = "The WireGuard instance ${name} must have an IPv4 address if a peer has an IPv4 address.";
          }
          {
            assertion = peer.ipv6 != null -> instance.ipv6 != null;
            message = "The WireGuard instance ${name} must have an IPv6 address if a peer has an IPv6 address.";
          }
          {
            assertion = peer.ipv4 != null || peer.ipv6 != null;
            message = "At least one IP address must be set for Wireguard peer ${name} of instance ${name}.";
          }
        ])
        instance.peers;

      multivpn.vpnInterfaces = [dev];

      networking.nat.enableIPv6 = mkIf (instance.ipv6 != null) true;

      networking = {
        firewall.allowedUDPPorts = mkIf (!instance.enableUDP2RAW) [instance.port];
        firewall.allowedTCPPorts = mkIf instance.enableUDP2RAW [instance.port];

        wireguard.interfaces.${dev} = {
          ips =
            optional (cfg.ipv4 != null) "${cfg.ipv4}/24"
            ++ optional (cfg.ipv6 != null) "${cfg.ipv6}/24";
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
          peers =
            concatMap (peer: {
              allowedIPs =
                optional (peer.ipv4 != null) "${cfg.ipv4}/32"
                ++ optional (peer.ipv6 != null) "${cfg.ipv6}/128";
              inherit (peer) publicKey;
            })
            cfg.peers;
          extraOptions = instance.amneziaWGOptions;
        };
      };

      multivpn.udp2raw.servers.${name} = mkIf instance.enableUDP2RAW {
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
          public=$(wg pubkey < ${escapeShellArg cfg.privateKeyFile})
          cat > "$dir/wg.conf" <<EOF
          [Interface]
          PrivateKey = <private key>
          Address = ${concatStringsSep "," (optional (instance.ipv4 != null) "<ipv4>/32" ++ optional (instance.ipv6 != null) "<ipv6>/128")}
          ${optionalString instance.enableUDP2RAW ''
            MTU = ${toString udp2rawMTU}
          ''}
          ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
              ${name} = ${toString value}
            '')
            instance.amneziaWGOptions)}

          [Peer]
          Endpoint = $domain:${toString instance.port}
          PublicKey = $public
          AllowedIPs = ${concatStringsSep "," (optional (instance.ipv4 != null) "0.0.0.0/0" ++ optional (instance.ipv6 != null) "::/0")}
          PersistentKeepalive = 25
          EOF
        '';
      };
    })
    cfg.instances);
}
