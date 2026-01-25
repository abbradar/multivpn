{
  config,
  lib,
  ...
}:
with lib; {
  options = {
    multivpn = {
      enable = mkEnableOption "MultiVPN module";

      domain = mkOption {
        type = types.str;
        description = "Host domain name.";
      };
    };
  };
}
