{ config, pkgs, lib, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.open = true;
  hardware.nvidia.nvidiaSettings = true;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.latest;
  hardware.graphics.extraPackages = with pkgs; [ nvidia-vaapi-driver vulkan-loader vulkan-validation-layers ];
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [ vulkan-loader ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa-demos
    clinfo
    libva-utils
  ];
}
