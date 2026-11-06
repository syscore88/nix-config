{ config, pkgs, ... }:

let
  inherit (pkgs.lib.gvariant) mkTuple mkInt32;
in
{
  virtualisation.libvirtd.enable = pkgs.lib.mkForce true;
  programs.virt-manager.enable = pkgs.lib.mkForce true;
  virtualisation.spiceUSBRedirection.enable = pkgs.lib.mkForce true;

  users.groups.libvirtd.members = [ "__INSTALL_USER__" ];

  networking.firewall.trustedInterfaces = [ "virbr0" ];

  systemd.services.libvirt-default-subnet = {
    description = "Move libvirt default network off a colliding subnet";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.virtualisation.libvirtd.package pkgs.iproute2 pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip -4 -o addr show | awk '$2 != "virbr0" && $4 ~ /^192\.168\.122\./ {found=1} END {exit !found}' || exit 0
      xml="$(virsh net-dumpxml default --inactive)" || exit 0
      echo "$xml" | grep -q '192\.168\.122\.' || exit 0
      echo "$xml" | sed 's/192\.168\.122\./192.168.150./g' > /tmp/libvirt-default.xml
      virsh net-destroy default || true
      virsh net-undefine default || true
      virsh net-define /tmp/libvirt-default.xml
      virsh net-autostart default
      virsh net-start default
      rm -f /tmp/libvirt-default.xml
    '';
  };

  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/virt-manager/virt-manager" = {
          manager-window-height = mkInt32 297;
          manager-window-width = mkInt32 478;
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