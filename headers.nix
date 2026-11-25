{ config, pkgs, ... }:

{
  environment.systemPackages = [
    config.boot.kernelPackages.kernel.dev
    pkgs.linuxHeaders
    pkgs.gcc
    pkgs.gnumake
    pkgs.elfutils
    pkgs.pkg-config
  ];

  environment.pathsToLink = [
    "/lib/modules"
    "/include"
  ];
}