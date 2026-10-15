{ pkgs, ... }:

{
  security.polkit.enable = pkgs.lib.mkForce true;

  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
