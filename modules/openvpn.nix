{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  rootCfg = config.multivpn;
  cfg = rootCfg.openvpn;
  dev = "vpn-ovpn";
  port = 1194;

  clientConfig = pkgs.writeTextDir "client.ovpn" ''
    proto udp
    remote ${rootCfg.domain}
    port ${toString port}
    nobind
    dev tun
    topology subnet
    pull

    persist-tun
    persist-key
    auth-nocache

    tls-client
    key client.key
    cert client.crt
    ca ca.crt
    tls-auth ta.key 1
    cipher AES-256-GCM
  '';
in {
  options = {
    multivpn.openvpn = {
      enable = mkEnableOption "OpenVPN support";

      subnet = mkOption {
        type = types.str;
        default = "10.0.175.0";
        description = "Network subnet that OpenVPN uses.";
      };
    };
  };

  config = mkIf (rootCfg.enable && cfg.enable) {
    multivpn.vpnInterfaces = [dev];

    networking.firewall.allowedUDPPorts = [port];

    # TODO: IPv6
    services.openvpn.servers.server.config = ''
      proto udp6
      port ${toString port}
      dev ${dev}
      dev-type tun
      topology subnet
      server ${cfg.subnet} 255.255.255.0

      persist-tun
      persist-key
      user openvpn
      group openvpn

      tls-server
      key /var/lib/openvpn-server/server.key
      cert /var/lib/openvpn-server/server.crt
      ca /var/lib/openvpn-server/ca.crt
      tls-auth /var/lib/openvpn-server/ta.key 0
      dh ${config.security.dhparams.path}/openvpn.pem
      duplicate-cn
      cipher AES-256-GCM

      ping-timer-rem
      keepalive 10 60
    '';

    security.dhparams = {
      enable = true;
      params.openvpn = 2048;
    };

    systemd.services = {
      init-openvpn-server = {
        description = "Generate secrets for the OpenVPN server.";
        before = ["openvpn-server.service"];
        wantedBy = ["multi-user.target" "openvpn-server.service"];
        path = with pkgs; [easyrsa openvpn];
        environment.EASYRSA_BATCH = "1";
        serviceConfig = {
          Type = "oneshot";
          User = "openvpn";
          Group = "openvpn";
          StateDirectory = "openvpn-server";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/openvpn-server";
        };
        script = ''
          if [ -e server.key ]; then
            echo "Key already exists."
            exit 0
          fi

          easyrsa init-pki
          easyrsa --nopass build-ca
          easyrsa --nopass build-server-full server
          easyrsa --nopass build-client-full client

          ln -s pki/ca.crt ca.crt
          ln -s pki/issued/server.crt server.crt
          ln -s pki/private/server.key server.key
          ln -s pki/issued/client.crt client.crt
          ln -s pki/private/client.key client.key

          openvpn --genkey --secret ta.key
        '';
      };

      vpn-credentials-openvpn = {
        description = "Prepare the client credentials for OpenVPN.";
        wantedBy = ["multi-user.target"];
        after = ["init-openvpn-server.service"];
        wants = ["init-openvpn-server.service"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "vpn-credentials";
          StateDirectoryMode = "0700";
          WorkingDirectory = "/var/lib/vpn-credentials";
        };
        script = ''
          mkdir -p openvpn
          cp -L --no-preserve=all \
            /var/lib/openvpn-server/{ca.crt,client.{crt,key},ta.key} \
            ${clientConfig}/client.ovpn \
            openvpn/
        '';
      };
    };

    users = {
      users.openvpn = {
        isSystemUser = true;
        group = "openvpn";
      };
      groups.openvpn = {};
    };
  };
}
