{ pkgs, ... }:

{
  boot.extraModulePackages = [ pkgs.linuxPackages_xanmod_latest.vhba ];

  services.udev.extraRules = ''
    KERNEL=="vhba_ctl", MODE="0660", OWNER="root", GROUP="wheel"
  '';

  services.dbus.packages = [ pkgs.cdemu-daemon ];

  systemd.user.services.cdemu-daemon = {
    description = "CDEmu daemon";
    serviceConfig = {
      Type = "dbus";
      BusName = "net.sf.cdemu.CDEmuDaemon";
      ExecStart = "${pkgs.cdemu-daemon}/bin/cdemu-daemon --config-file \"%h/.config/cdemu-daemon\"";
      Restart = "no";
    };
  };
}
