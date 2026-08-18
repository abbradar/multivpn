{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.protocols.wireguard;
  # UDP2RAW adds 60 bytes of overhead, plus 36 bytes for aes128cbc padding (16)
  # and the hmac_sha1 auth tag (20). 1340 is the max that keeps the worst-case
  # packet within 1500 over an IPv6 outer path (which always carries a faketcp
  # TCP timestamp option), while leaving a small margin.
  udp2rawMTU = 1340;

  peerModule = {...}: {
    options = {
      ipv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Peer's private IPv4 address.
        '';
      };

      ipv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
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

  instanceModule = {name, ...}: {
    options = {
      ipv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "10.0.174.1";
        description = "Network address and a /24 subnet that Wireguard uses.";
      };

      ipv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "fd80:f700:3bb2::1";
        description = "Network address and a /64 subnet that Wireguard uses.";
      };

      port = mkOption {
        type = types.int;
        description = "Port to listen on.";
      };

      enableUDP2RAW = mkEnableOption "UDP2RAW support";

      internalPort = mkOption {
        type = types.int;
        description = "Local port to listen on internally. Needed for UDP2RAW.";
      };

      udp2rawKey = mkOption {
        type = types.str;
        description = "udp2raw shared secret for this instance; must match the client connecting to it. Required when enableUDP2RAW is set. Generate with `openssl rand -base64 32`.";
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

      device = mkOption {
        type = types.str;
        internal = true;
        description = "WireGuard device.";
      };
    };

    config = {
      device = "vpn-wg-${name}";
    };
  };

  # AmneziaWG instances run via the userspace daemon (amneziawg-go); plain
  # WireGuard instances keep using the kernel-backed networking.wireguard module.
  amneziaInstances = filterAttrs (_: instance: instance.amneziaWGOptions != {}) cfg.instances;
  plainInstances = filterAttrs (_: instance: instance.amneziaWGOptions == {}) cfg.instances;

  # wg-level config applied via `awg setconf` (no Address/MTU, which awg rejects;
  # those are handled by systemd-networkd). PrivateKey is prepended at runtime.
  mkWgConfBody = instance: let
    listenPort =
      if instance.enableUDP2RAW
      then instance.internalPort
      else instance.port;
    ifaceLines =
      ["ListenPort = ${toString listenPort}"]
      ++ mapAttrsToList (k: v: "${k} = ${toString v}") instance.amneziaWGOptions;
    peerText = peer:
      "\n[Peer]\n"
      + "PublicKey = ${peer.publicKey}\n"
      + "AllowedIPs = ${concatStringsSep ", " (
        optional (peer.ipv4 != null) "${peer.ipv4}/32"
        ++ optional (peer.ipv6 != null) "${peer.ipv6}/128"
      )}\n";
  in
    pkgs.writeText "${instance.device}.conf"
    (concatStringsSep "\n" ifaceLines + "\n" + concatMapStrings peerText instance.peers);

  mkAwgService = name: instance: let
    wgConf = mkWgConfBody instance;
    dev = instance.device;
    confPath = "/run/amneziawg-${name}/${dev}.conf";
  in {
    description = "AmneziaWG (userspace) tunnel - ${name}";
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
      RuntimeDirectory = "amneziawg-${name}";
      RuntimeDirectoryMode = "0700";
    };
    # Apply the wg-level crypto config (private key, peers, AmneziaWG options).
    # Addressing, MTU and bringing the link up are handled by systemd-networkd.
    postStart = ''
      {
        echo '[Interface]'
        printf 'PrivateKey = %s\n' "$(cat ${escapeShellArg instance.privateKeyFile})"
        cat ${wgConf}
      } > ${escapeShellArg confPath}
      awg setconf ${dev} ${escapeShellArg confPath}
    '';
  };
in {
  options = {
    multivpn.protocols.wireguard = {
      instances = mkOption {
        type = types.attrsOf (types.submodule instanceModule);
        default = {};
        description = "WireGuard/AmneziaWG instances.";
      };
    };
  };

  config = {
    assertions =
      concatLists (mapAttrsToList (name: instance:
        [
          {
            assertion = instance.ipv4 != null || instance.ipv6 != null;
            message = "At least one IP address must be set for Wireguard instance ${name}.";
          }
          {
            assertion = instance.enableUDP2RAW -> instance.udp2rawKey != "";
            message = "udp2rawKey must be set for Wireguard instance ${name} when enableUDP2RAW is set.";
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
        instance.peers)
      cfg.instances)
      ++ [
        {
          assertion = amneziaInstances != {} -> config.systemd.network.enable;
          message = "multivpn: AmneziaWG instances require systemd-networkd; set networking.useNetworkd = true (or systemd.network.enable = true).";
        }
      ];

    multivpn = {
      firewall.vpnInterfaces = mapAttrsToList (name: instance: instance.device) cfg.instances;

      services.udp2raw.servers = concatMapAttrs (name: instance:
        optionalAttrs instance.enableUDP2RAW {
          ${instance.device} = {
            port = instance.port;
            destination = "127.0.0.1";
            destinationPort = instance.internalPort;
            key = instance.udp2rawKey;
          };
        })
      cfg.instances;
    };

    networking = {
      nat.enableIPv6 = mkMerge (mapAttrsToList (name: instance: mkIf (instance.ipv6 != null) true) cfg.instances);

      firewall = {
        allowedUDPPorts = mkMerge (mapAttrsToList (name: instance: mkIf (!instance.enableUDP2RAW) [instance.port]) cfg.instances);
        allowedTCPPorts = mkMerge (mapAttrsToList (name: instance: mkIf instance.enableUDP2RAW [instance.port]) cfg.instances);
      };

      # AmneziaWG instances are handled below via a systemd service running
      # amneziawg-go; only plain WireGuard instances use this kernel-backed path.
      wireguard.interfaces = mapAttrs' (name: instance:
        nameValuePair instance.device {
          ips =
            optional (instance.ipv4 != null) "${instance.ipv4}/24"
            ++ optional (instance.ipv6 != null) "${instance.ipv6}/24";
          mtu = mkIf instance.enableUDP2RAW udp2rawMTU;
          privateKeyFile = instance.privateKeyFile;
          listenPort =
            if instance.enableUDP2RAW
            then instance.internalPort
            else instance.port;
          peers =
            map (peer: {
              allowedIPs =
                optional (peer.ipv4 != null) "${peer.ipv4}/32"
                ++ optional (peer.ipv6 != null) "${peer.ipv6}/128";
              inherit (peer) publicKey;
            })
            instance.peers;
        })
      plainInstances;
    };

    # systemd-networkd (already enabled system-wide) assigns addresses/MTU and
    # brings up the userspace AmneziaWG interfaces created by the services above.
    systemd.network.networks = mapAttrs' (name: instance:
      nameValuePair "40-${instance.device}" {
        matchConfig.Name = instance.device;
        address =
          optional (instance.ipv4 != null) "${instance.ipv4}/24"
          ++ optional (instance.ipv6 != null) "${instance.ipv6}/24";
        linkConfig = optionalAttrs instance.enableUDP2RAW {
          MTUBytes = toString udp2rawMTU;
        };
      })
    amneziaInstances;

    systemd.services = mkMerge [
      (mapAttrs' (name: instance:
        nameValuePair "amneziawg-${name}" (mkAwgService name instance))
      amneziaInstances)

      (mapAttrs' (name: instance:
        nameValuePair "vpn-credentials-wireguard-${name}" {
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
            public=$(wg pubkey < ${escapeShellArg instance.privateKeyFile})
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
        })
      cfg.instances)
    ];
  };
}
