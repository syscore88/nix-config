{ pkgs, ... }:

{
  zramSwap = {
    enable = pkgs.lib.mkForce true;
    algorithm = pkgs.lib.mkForce "lz4";
  };

  services.swapspace.enable = pkgs.lib.mkForce true;
}
