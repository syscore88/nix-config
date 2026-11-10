{ config, pkgs, lib, ... }:

{
  services.xserver.videoDrivers = [ "modesetting" ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [ intel-media-driver intel-compute-runtime vulkan-loader vulkan-validation-layers ];
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [ intel-media-driver vulkan-loader ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa-demos
    clinfo
    libva-utils
  ];
}
