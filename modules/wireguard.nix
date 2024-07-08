{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn.wireguard;

  dev = "vpn-wg";
  port = 51820;

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
          Peer's public key.
        '';
      };
    };
  };

  mkPeer = peer: {
    allowedIPs = ["${peer.ip}/32"];
    inherit (peer) publicKey;
  };
in {
  options = {
    multivpn.wireguard = {
      enable = mkEnableOption "OpenVPN support";

      ip = mkOption {
        type = types.str;
        default = "10.0.174.0";
        description = "Network subnet that OpenVPN uses.";
      };

      privateKeyFile = mkOption {
        type = types.path;
        description = "WireGuard private key path.";
      };

      peers = mkOption {
        type = types.listOf (types.submodule peerModule);
        default = {};
        description = "WireGuard peers.";
      };
    };
  };

  config = mkIf (config.multivpn.enable && cfg.enable) {
    multivpn.vpnInterfaces = [dev];

    networking = {
      firewall.allowedUDPPorts = [port];
      # FIXME: IPv6
      wireguard.interfaces.${dev} = {
        ips = ["${cfg.ip}/24"];
        privateKeyFile = cfg.privateKeyFile;
        listenPort = port;
        peers = map mkPeer cfg.peers;
      };
    };
  };
}
