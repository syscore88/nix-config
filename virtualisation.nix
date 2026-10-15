{ pkgs, ... }:

let
  inherit (pkgs.lib.gvariant) mkTuple mkInt32;
in
{
  virtualisation.libvirtd.enable = pkgs.lib.mkForce true;
  programs.virt-manager.enable = pkgs.lib.mkForce true;
  virtualisation.spiceUSBRedirection.enable = pkgs.lib.mkForce true;

  users.groups.libvirtd.members = [ "__INSTALL_USER__" ];

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/virt-manager/virt-manager" = {
          manager-window-height = 297;
          manager-window-width = 478;
          xmleditor-enabled = true;
        };
        "org/virt-manager/virt-manager/confirm" = {
          delete-storage = false;
          forcepoweroff = false;
        };
        "org/virt-manager/virt-manager/connections" = {
          autoconnect = [ "qemu:///system" ];
          uris = [ "qemu:///system" ];
        };
        "org/virt-manager/virt-manager/conns/qemu:system" = {
          window-size = mkTuple [ (mkInt32 800) (mkInt32 600) ];
        };
        "org/virt-manager/virt-manager/details" = {
          show-toolbar = true;
        };
        "org/virt-manager/virt-manager/new-vm" = {
          cpu-default = "host-passthrough";
          firmware = "uefi";
          graphics-type = "spice";
          storage-format = "raw";
        };
        "org/virt-manager/virt-manager/stats" = {
          enable-disk-poll = true;
          enable-memory-poll = true;
          enable-net-poll = true;
        };
        "org/virt-manager/virt-manager/vmlist-fields" = {
          disk-usage = false;
          network-traffic = false;
        };
      };
    }
  ];
}
