{ pkgs, ... }:

{
  programs.dconf.enable = pkgs.lib.mkForce true;

  services.geoclue2.enable = pkgs.lib.mkForce true;

  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "3s";
  };

  environment.sessionVariables = {
    EDITOR = "nano";
    GTK_USE_PORTAL = "1";
    OBS_VKCAPTURE_QUIET = "1";
  };

  xdg.portal = {
    enable = pkgs.lib.mkForce true;
    xdgOpenUsePortal = pkgs.lib.mkForce true;
  };

  services.envfs.enable = pkgs.lib.mkForce true;
  services.printing.enable = pkgs.lib.mkForce false;

  services.flatpak.enable = pkgs.lib.mkForce true;

  programs.appimage = {
    enable = pkgs.lib.mkForce true;
    binfmt = pkgs.lib.mkForce true;
  };
}
