{ pkgs, ... }:

{
  security.polkit.enable = pkgs.lib.mkForce true;

  security.apparmor.enable = false;
}
```[cite: 1]
