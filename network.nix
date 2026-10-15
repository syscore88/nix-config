{ pkgs, ... }:

{
  networking.networkmanager.dns = "default";
  environment.etc."NetworkManager/conf.d/global-dns.conf".text = ''
    [global-dns]

    [global-dns-domain-*]
    servers=1.1.1.2,1.0.0.2,2606:4700:4700::1112,2606:4700:4700::1002
  '';

  services.openssh.enable = pkgs.lib.mkForce false;

  networking.firewall.allowedTCPPorts = [ 22 ];
}
