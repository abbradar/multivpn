{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.protocols.amneziawg;

  peerModule = {...}: {
    options = {
      ipv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Peer's private IPv4 address.";
      };

      ipv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Peer's private IPv6 address.";
      };

      publicKey = mkOption {
        type = types.str;
        description = "Peer's public key. Generate the private key with `awg genkey`, then get the public key with `awg pubkey`.";
      };
    };
  };

  instanceModule = {name, ...}: {
    options = {
      ipv4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "10.0.175.1";
        description = "Network address and a /24 subnet that AmneziaWG uses.";
      };

      ipv6 = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "fd80:f700:3bb3::1";
        description = "Network address and a /64 subnet that AmneziaWG uses.";
      };

      port = mkOption {
        type = types.int;
        description = "UDP port to listen on.";
      };

      privateKeyFile = mkOption {
        type = types.path;
        description = "Private key path. Generate with `awg genkey`.";
      };

      headerProtectionKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "AmneziaWG 3 header protection key path. Generate with `awg genkey`.";
      };

      settings = mkOption {
        type = types.attrsOf (types.oneOf [types.str types.int]);
        default = {};
        example = {
          S1 = 57;
          S2 = 108;
          H1 = "856961290-901569238";
        };
        description = "AmneziaWG options.";
      };

      peers = mkOption {
        type = types.listOf (types.submodule peerModule);
        default = [];
        description = "AmneziaWG peers.";
      };

      device = mkOption {
        type = types.str;
        internal = true;
        description = "AmneziaWG device.";
      };
    };

    config = {
      device = "vpn-awg-${name}";
    };
  };
in {
  options = {
    multivpn.protocols.amneziawg = {
      instances = mkOption {
        type = types.attrsOf (types.submodule instanceModule);
        default = {};
        description = "AmneziaWG instances.";
      };
    };
  };

  config = {
    assertions =
      optional (cfg.instances != {}) {
        assertion = config.systemd.network.enable;
        message = "multivpn: AmneziaWG instances are configured with systemd-networkd; set networking.useNetworkd = true.";
      }
      ++ concatLists (mapAttrsToList (name: instance:
        [
          {
            assertion = instance.ipv4 != null || instance.ipv6 != null;
            message = "At least one IP address must be set for AmneziaWG instance ${name}.";
          }
        ]
        ++ concatMap (peer: [
          {
            assertion = peer.ipv4 != null -> instance.ipv4 != null;
            message = "The AmneziaWG instance ${name} must have an IPv4 address if a peer has an IPv4 address.";
          }
          {
            assertion = peer.ipv6 != null -> instance.ipv6 != null;
            message = "The AmneziaWG instance ${name} must have an IPv6 address if a peer has an IPv6 address.";
          }
          {
            assertion = peer.ipv4 != null || peer.ipv6 != null;
            message = "At least one IP address must be set for each peer of AmneziaWG instance ${name}.";
          }
        ])
        instance.peers)
      cfg.instances);

    multivpn = {
      firewall.vpnInterfaces = mapAttrsToList (name: instance: instance.device) cfg.instances;

      services.amneziawg-go.interfaces = mapAttrs' (name: instance:
        nameValuePair instance.device {
          inherit (instance) privateKeyFile headerProtectionKeyFile settings;
          listenPort = instance.port;
          peers =
            map (peer: {
              inherit (peer) publicKey;
              allowedIPs =
                optional (peer.ipv4 != null) "${peer.ipv4}/32"
                ++ optional (peer.ipv6 != null) "${peer.ipv6}/128";
            })
            instance.peers;
        })
      cfg.instances;
    };

    networking = {
      nat.enableIPv6 = mkMerge (mapAttrsToList (name: instance: mkIf (instance.ipv6 != null) true) cfg.instances);
      firewall.allowedUDPPorts = mapAttrsToList (name: instance: instance.port) cfg.instances;
    };

    systemd.network.networks = mapAttrs' (name: instance:
      nameValuePair "40-${instance.device}" {
        matchConfig.Name = instance.device;
        address =
          optional (instance.ipv4 != null) "${instance.ipv4}/24"
          ++ optional (instance.ipv6 != null) "${instance.ipv6}/64";
      })
    cfg.instances;

    systemd.services = mapAttrs' (name: instance:
      nameValuePair "vpn-credentials-amneziawg-${name}" {
        description = "Prepare the client credentials for AmneziaWG.";
        wantedBy = ["multi-user.target"];
        path = with pkgs; [amneziawg-tools];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          dir=amneziawg-${escapeShellArg name}
          mkdir -p "$dir"
          domain=${escapeShellArg rootCfg.domain}
          public=$(awg pubkey < ${escapeShellArg instance.privateKeyFile})
          ${optionalString (instance.headerProtectionKeyFile != null) ''
            headerProtectionKey=$(cat ${escapeShellArg instance.headerProtectionKeyFile})
          ''}
          cat > "$dir/awg.conf" <<EOF
          [Interface]
          PrivateKey = <private key>
          Address = ${concatStringsSep "," (optional (instance.ipv4 != null) "<ipv4>/32" ++ optional (instance.ipv6 != null) "<ipv6>/128")}
          ${concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${toString v}") instance.settings)}
          ${optionalString (instance.headerProtectionKeyFile != null) "HeaderProtectionKey = $headerProtectionKey"}

          [Peer]
          Endpoint = $domain:${toString instance.port}
          PublicKey = $public
          AllowedIPs = ${concatStringsSep "," (optional (instance.ipv4 != null) "0.0.0.0/0" ++ optional (instance.ipv6 != null) "::/0")}
          PersistentKeepalive = 25
          EOF
        '';
      })
    cfg.instances;
  };
}
