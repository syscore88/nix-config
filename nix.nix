{ pkgs, ... }:

{
  nixpkgs.config.allowInsecurePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "electron" "ventoy" ];

  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;

  nix.gc = {
    automatic = pkgs.lib.mkForce true;
    dates = pkgs.lib.mkForce "daily";
    options = pkgs.lib.mkForce "--delete-generations +2";
  };

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" ];
  };
}
