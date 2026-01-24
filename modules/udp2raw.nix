{ config, ... }:

{
  config = {
    systemd.services = mapAttrs' (name: iface:
      nameValuePair "multivpn-udp2raw-server-${name}" {
        description = "UDP2RAW server for ${name}.";
        wantedBy = ["multi-user.target"];
        wants = ["network.target"];
        after = ["network.target"];
        unitConfig = {
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          Restart = "always";
          RestartSec = 5;
          # We effectively disable mtu-warn.
        ExecStart = [
	  "${pkgs.udp2raw}/bin/udp2raw"
	  "-s"
	  "-l" "${iface.address}:${toString iface.port}"
	  "-r" iface.destination
          "-a"
	  "--mtu-warn" "1500"
	  "--cipher-mode" "none"
	  "--auth-mode" "none"
        ];
        };
      })
  };
}
