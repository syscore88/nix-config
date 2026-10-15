{ pkgs, ... }:

{
  environment.plasma6.excludePackages =
    builtins.filter (p: p != null)
      (map (n: pkgs.kdePackages.${n} or null) [
        "elisa"
        "kwalletmanager"
        "plasma-browser-integration"
        "plasma-vault"
        "krfb"
        "discover"
      ]);

  nixpkgs.overlays = [
    (final: prev: {
      kdePackages = prev.kdePackages.overrideScope (kfinal: kprev: {
        kwalletmanager = kprev.kwalletmanager.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            rm -f $out/share/applications/*kwalletmanager*.desktop
          '';
        });
      });
    })
  ];

  environment.gnome.excludePackages =
    builtins.filter (p: p != null)
      (map (n: pkgs.${n} or null) [
        "gnome-calendar"
        "gnome-clocks"
        "gnome-music"
        "gnome-user-docs"
        "gnome-contacts"
        "gnome-maps"
        "gnome-weather"
        "yelp"
        "evolution"
        "evolution-ews"
        "epiphany"
        "decibels"
        "rhythmbox"
        "showtime"
        "gnome-software"
      ]);

  environment.xfce.excludePackages =
    builtins.filter (p: p != null)
      (map (n: pkgs.${n} or null) [
        "parole"
      ]);
}
