{lib}:
with lib; rec {
  isIPv6 = s: !hasInfix "/" s && (builtins.tryEval (network.ipv6.fromString s).address).success;

  isIPv4 = s: let
    octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
  in
    builtins.match "${octet}\\.${octet}\\.${octet}\\.${octet}" s != null;

  isIP = s: isIPv4 s || isIPv6 s;

  # nftables address family of an IP literal.
  nftFamily = s:
    if isIPv6 s
    then "ip6"
    else "ip";

  # "host:port", with an IPv6 host in brackets.
  hostPort = host: port:
    if isIPv6 host
    then "[${host}]:${toString port}"
    else "${host}:${toString port}";

  types = {
    ipAddress =
      lib.types.addCheck lib.types.str isIP
      // {
        name = "ipAddress";
        description = "IPv4 or IPv6 address";
      };
  };
}
