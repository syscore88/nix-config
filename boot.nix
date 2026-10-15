{ pkgs, ... }:

{
  boot.supportedFilesystems = [ "exfat" "btrfs" "ntfs" ];

  boot.tmp.cleanOnBoot = pkgs.lib.mkForce true;

  boot.plymouth = {
    enable = pkgs.lib.mkForce true;
    theme = pkgs.lib.mkForce "bgrt";
  };

  boot.consoleLogLevel = pkgs.lib.mkForce 2;
  boot.initrd.verbose = pkgs.lib.mkForce false;

  boot.loader.timeout = pkgs.lib.mkForce 0;

  boot.loader.systemd-boot.configurationLimit = pkgs.lib.mkForce 2;
}
