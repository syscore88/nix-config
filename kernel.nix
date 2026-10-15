{ pkgs, ... }:

{
  boot.kernelPackages = pkgs.lib.mkForce pkgs.linuxPackages_xanmod_latest;

  boot.kernelParams = [
    "quiet"
    "splash"
    "udev.log_level=3"
    "systemd.show_status=auto"
    "nohibernate"
    "usbcore.autosuspend=-1"
    "mitigations=off"
  ];

  boot.kernel.sysctl = {
    "kernel.split_lock_mitigate" = 0;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "net.ipv4.tcp_fin_timeout" = 5;
    "vm.max_map_count" = 2147483642;
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_bytes" = 50331648;
    "vm.dirty_background_bytes" = 16777216;
    "vm.dirty_expire_centisecs" = 3000;
    "vm.dirty_writeback_centisecs" = 1500;
    "vm.min_free_kbytes" = 59030;
  };
}
