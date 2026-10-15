{ pkgs, ... }:

{
  systemd.services.flatpak-install-apps = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
      flatpak update --appstream || true
      flatpak info com.github.tchx84.Flatseal &>/dev/null || flatpak install -y --noninteractive flathub com.github.tchx84.Flatseal || true
      flatpak info it.mijorus.gearlever &>/dev/null || flatpak install -y --noninteractive flathub it.mijorus.gearlever || true
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "10min";
    };
  };
}
