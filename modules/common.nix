{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.multivpn;
  addresses = import ./addresses.nix;
in {
  options = {
    multivpn = {
      enable = mkEnableOption "MultiVPN module";

      externalLocalAddress4 = mkOption {
        type = types.str;
        description = "Local IPv4 network address of the external network interface.";
      };

      domain = mkOption {
        type = types.str;
        description = "Host domain name.";
      };

      vpnInterfaces = mkOption {
        type = types.listOf types.str;
        internal = true;
        default = [];
        description = "List of the VPN interfaces that submodules define.";
      };
    };
  };

  config = mkIf cfg.enable {
    networking = {
      firewall = {
        extraCommands = mkMerge [
          (mkBefore ''
            ip46tables -F multivpn-forward 2> /dev/null || true
            ip46tables -X multivpn-forward 2> /dev/null || true
            ip46tables -N multivpn-forward

            # Allow established.
            ip46tables -A multivpn-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
          '')

          (mkAfter ''
            ip46tables -A FORWARD -j multivpn-forward
          '')

          ''
            ip46tables -F multivpn-block-private 2> /dev/null || true
            ip46tables -X multivpn-block-private 2> /dev/null || true
            ip46tables -N multivpn-block-private

            ${concatMapStringsSep "\n" (ip4: ''
                iptables -A multivpn-forward -d ${escapeShellArg ip4} -j DROP
              '')
              addresses.privateNetworks4}
            ${concatMapStringsSep "\n" (ip6: ''
                ip6tables -A multivpn-forward -d ${escapeShellArg ip6} -j DROP
              '')
              addresses.privateNetworks6}
            ip46tables -A multivpn-block-private -j RETURN

            ${concatMapStringsSep "\n" (dev: ''
                ip46tables -A multivpn-forward -i ${escapeShellArg dev} -j multivpn-block-private
              '')
              cfg.vpnInterfaces}
          ''
        ];
        extraStopCommands = mkAfter ''
          ip46tables -D FORWARD -j multivpn-forward 2>/dev/null || true
        '';
      };

      nat = {
        enable = true;
        internalInterfaces = cfg.vpnInterfaces;
      };
    };
  };
}
