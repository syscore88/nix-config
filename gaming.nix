{ pkgs, ... }:

{
  boot.kernelModules = [ "ntsync" ];

  programs.gamemode.enable = pkgs.lib.mkForce true;

  programs.gamescope = {
    enable = pkgs.lib.mkForce true;
    capSysNice = false;
  };

  programs.steam.enable = true;
}
