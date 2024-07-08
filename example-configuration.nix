{
  multivpn = {
    enable = true;

    # Set to your host's domain.
    # Host should have at least the following records (NS is for Iodine):
    # A example.com 1.2.3.4
    # NS example.com 1.2.3.4
    domain = "example.com";
    # Set to your local IP address of the external interface.
    # Find it out with: `ip -4 addr show`
    externalLocalAddress4 = "192.168.1.1";

    ss-legacy = {
      enable = true;
      password = "changeme";
      # Use a strong, randomly generated password.
      # Generate with: `openssl rand -base64 30`
    };

    ss2022 = {
      enable = true;
      key = "changeme";
      # Use a random Base64-encoded 32 byte value.
      # Generate with: `openssl rand -base64 32`
    };

    vless = {
      enable = true;
      id = "changeme";
      # Use a random UUID.
      # Generate with: `uuidgen`
    };

    socks5 = {
      enable = true;
      password = "changeme";
      # Use a strong, randomly generated password
      # Generate with: `openssl rand -base64 30`
    };

    mtprotoproxy = {
      enable = true;
      key = "changeme";
      # Use a 32-character hexadecimal key
      # Generate with: `openssl rand -hex 16`
    };

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
