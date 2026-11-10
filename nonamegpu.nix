{ config, pkgs, lib, ... }:

{
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [ vulkan-loader vulkan-validation-layers ocl-icd ];
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [ vulkan-loader ];

  environment.systemPackages = with pkgs; [
    vulkan-tools
    mesa-demos
    clinfo
    libva-utils
  ];
}
