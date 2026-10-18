{ config, pkgs, lib, ... }:

let
  lanzaboote = builtins.getFlake "github:nix-community/lanzaboote/v0.4.2";
in
{
  imports = [
    lanzaboote.nixosModules.lanzaboote
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote.enable = true;
  boot.lanzaboote.pkiBundle = "/var/lib/sbctl";

  environment.systemPackages = [ pkgs.sbctl ];
}
