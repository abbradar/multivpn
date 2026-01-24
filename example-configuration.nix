{pkgs, ...}: {
  multivpn = {
    # After deployed, you can find all the VPN server keys in `/var/lib/vpn-credentials`.
    enable = true;

    # Set to your host's domain.
    # Host should have at least the following records (NS is for Iodine):
    # A example.com 1.2.3.4
    # NS t.example.com 1.2.3.4
    domain = "example.com";

    ss-legacy = {
      enable = true;
      # Generate with `tr -dc A-Za-z0-9 </dev/urandom | head -c 32`
      password = "changeme";
    };

    ss2022 = {
      enable = true;
      # Generate with `openssl rand -base64 32`
      key = "changeme";
    };

    vless = {
      enable = true;
      # Generate with `uuidgen`
      id = "changeme";
    };

    socks5 = {
      enable = true;
      # Generate with `tr -dc A-Za-z0-9 </dev/urandom | head -c 32`
      password = "changeme";
    };

    iodine = {
      enable = true;
      # Generate with `tr -dc A-Za-z0-9 </dev/urandom | head -c 32`
      passwordFile = "/var/keys/iodine.key";
    };

    mtprotoproxy = {
      enable = true;
      # Generate with `openssl rand -hex 16`
      key = "changeme";
    };

    openvpn.enable = true;

    wireguard = {
      enable = true;
      # Generate with: `wg genkey`.
      privateKeyFile = "/var/keys/wireguard.key";
      peers = [
        # My laptop
        {
          ip = "10.0.174.2";
          publicKey = "changeme";
        }
      ];
    };
  };

  # Needed when VLESS is enabled.
  security.acme = {
    defaults.email = "example@example.com"; # Use a valid email address
    acceptTerms = true;
  };
}
