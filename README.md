# MultiVPN

This is a NixOS module which allows you to quickly deploy multiple VPN
protocols to circumvent censorship.

## Quickstart with cloud-config

If your hosting supports "user data" (cloud-init scripts), you can use the
provided [cloud-init configuration](cloud-init.yaml] to get started.

For example given Hetzner Cloud:

1. Open "Create a server" page;
2. Select an Ubuntu 24.04 image;
3. Select any instance type (CX32 or CPX21 are recommended);
4. *Important:* select your SSH key;
5. Paste [cloud-init configuration](cloud-init.yaml] into the "Cloud config"
   text box;
6. Create a server. Wait for 10 minutes; the machine should restart to NixOS;
7. Open `nano /etc/nixos/vpn.nix` and continue the configuration.

See instructions for other hosting providers at the
[nixos-infect](https://github.com/elitak/nixos-infect) page. You might need to
change the `PROVIDER` value in `cloud-init.yaml`, or execute the instructions
by yourself.

## Configuration

Refer to the [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/)
and [the example NixOS configuration](example-configuration.nix).
