{ pkgs, ... }:

{
  hardware.graphics = {
    enable = pkgs.lib.mkForce true;
    enable32Bit = pkgs.lib.mkForce true;
  };

  hardware.bluetooth.enable = pkgs.lib.mkForce true;

  services.fwupd.enable = pkgs.lib.mkForce true;
}
