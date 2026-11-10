{ config, pkgs, lib, ... }:

{
  services.xserver.videoDrivers = [ "amdgpu" ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [ rocmPackages.clr.icd vulkan-loader vulkan-validation-layers ];
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [ vulkan-loader ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa-demos
    clinfo
    libva-utils
  ];
}
