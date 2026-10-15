#!/usr/bin/env bash
# ============================
# SKRYPT KONFIGURACYJNY NIXOS
# ============================

set -Eeuo pipefail
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/kde-install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
    if [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ]; then
        sudo systemctl reboot
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() {
    echo -e "$1"
    echo -e "$1" >&3
}
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PREP="Przygotowywanie..."
    MSG_COPY="Kopiowanie plików..."
    MSG_CONFIG="Konfiguracja NixOS..."
    MSG_REBUILD="Przebudowa systemu (to może potrwać)..."
    MSG_OPTIMIZE="Optymalizacja..."
    MSG_FINALIZE="Finalizowanie..."
else
    MSG_PREP="Preparing..."
    MSG_COPY="Copying files..."
    MSG_CONFIG="Configuring NixOS..."
    MSG_REBUILD="Rebuilding system (this may take a while)..."
    MSG_OPTIMIZE="Optimization..."
    MSG_FINALIZE="Finalizing..."
fi

TOTAL_STEPS=5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER=$(whoami)
NIXOS_DIR="/etc/nixos"
CONF="$NIXOS_DIR/configuration.nix"

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    exit 1
fi

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
printf '\033[?7h' >&3

if ! grep -qx 'ID=nixos' /etc/os-release 2>/dev/null; then
    log_err "Ten skrypt działa tylko na NixOS." "This script works on NixOS only."
    exit 1
fi

if [[ ! -f "$CONF" ]]; then
    log_err "Nie znaleziono $CONF." "Could not find $CONF."
    exit 1
fi

sudo -v

(
    set +e
    trap - ERR
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done
) &
SUDO_KEEPALIVE_PID=$!

printf '\033[?7l' >&3

show_progress 0 $TOTAL_STEPS "$MSG_PREP"
show_progress 1 $TOTAL_STEPS "$MSG_PREP"

if [ -f "$SCRIPT_DIR/.update.sh" ]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

if [ -d "$SCRIPT_DIR/.local" ]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
fi

if [ -d "$SCRIPT_DIR/.config" ]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
fi

# ==========================================================
# 2. USTAWIENIA DO configuration.nix
# ==========================================================
show_progress 2 $TOTAL_STEPS "$MSG_CONFIG"

BACKUP="$CONF.bak-$(date +%Y%m%d_%H%M%S)"
sudo cp -a "$CONF" "$BACKUP"

BLOCK_TMP="$(mktemp)"
cat > "$BLOCK_TMP" <<'NIXMODULE_EOF'
  # --- install.sh: BEGIN (blok jest nadpisywany przy ponownym uruchomieniu skryptu) ---
  hardware.graphics = {
    enable = pkgs.lib.mkForce true;
    enable32Bit = pkgs.lib.mkForce true;
  };

  programs.dconf.enable = pkgs.lib.mkForce true;

  services.geoclue2.enable = pkgs.lib.mkForce true;

  boot.extraModulePackages = [ pkgs.linuxPackages_xanmod_latest.vhba ];

  services.udev.extraRules = ''
    KERNEL=="vhba_ctl", MODE="0660", OWNER="root", GROUP="wheel"
  '';

  services.dbus.packages = [ pkgs.cdemu-daemon ];

  systemd.user.services.cdemu-daemon = {
    description = "CDEmu daemon";
    serviceConfig = {
      Type = "dbus";
      BusName = "net.sf.cdemu.CDEmuDaemon";
      ExecStart = "${pkgs.cdemu-daemon}/bin/cdemu-daemon --config-file \"%h/.config/cdemu-daemon\"";
      Restart = "no";
    };
  };

  hardware.bluetooth.enable = pkgs.lib.mkForce true;
  boot.supportedFilesystems = [ "exfat" "btrfs" "ntfs" ];

  boot.tmp.cleanOnBoot = pkgs.lib.mkForce true;
  boot.kernelPackages = pkgs.lib.mkForce pkgs.linuxPackages_xanmod_latest;
  boot.kernelModules = [ "ntsync" ];

  networking.networkmanager.dns = "default";
  environment.etc."NetworkManager/conf.d/global-dns.conf".text = ''
    [global-dns]

    [global-dns-domain-*]
    servers=1.1.1.2,1.0.0.2,2606:4700:4700::1112,2606:4700:4700::1002
  '';

  boot.plymouth = {
    enable = pkgs.lib.mkForce true;
    theme = pkgs.lib.mkForce "bgrt";
  };

  boot.consoleLogLevel = pkgs.lib.mkForce 2;
  boot.initrd.verbose = pkgs.lib.mkForce false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "udev.log_level=3"
    "systemd.show_status=auto"
    "nohibernate"
    "usbcore.autosuspend=-1"
    "mitigations=off"
  ];

  boot.kernel.sysctl = {
    "kernel.split_lock_mitigate" = 0;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "net.ipv4.tcp_fin_timeout" = 5;
    "vm.max_map_count" = 2147483642;
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_bytes" = 50331648;
    "vm.dirty_background_bytes" = 16777216;
    "vm.dirty_expire_centisecs" = 3000;
    "vm.dirty_writeback_centisecs" = 1500;
    "vm.min_free_kbytes" = 59030;
  };

  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "3s";
  };

  zramSwap = {
    enable = pkgs.lib.mkForce true;
    algorithm = pkgs.lib.mkForce "lz4";
  };

  boot.loader.timeout = pkgs.lib.mkForce 0;

  boot.loader.systemd-boot.configurationLimit = pkgs.lib.mkForce 2;

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

  environment.sessionVariables = {
    EDITOR = "nano";
    GTK_USE_PORTAL = "1";
    OBS_VKCAPTURE_QUIET = "1";
    MESA_SHADER_CACHE_MAX_SIZE = "24G";
  };

  xdg.portal = {
    enable = pkgs.lib.mkForce true;
    xdgOpenUsePortal = pkgs.lib.mkForce true;
  };

  environment.systemPackages = with pkgs; [
    dconf-editor
    cdemu-daemon
    cdemu-client
    gcdemu
    steam-run
    brave
    google-chrome
    faugus-launcher
    kdePackages.ghostwriter
    libreoffice-fresh
    hunspellDicts.pl_PL
    gimp
    gimpPlugins.gmic
    krita
    krita-plugin-gmic
    gmic
    discord
    telegram-desktop
    qbittorrent
    audacity
    handbrake
    kdePackages.kdenlive
    soundconverter
    mixxx
    qmmp
    vlc
    opencode-desktop
    wine-staging
    winetricks
    mangohud
    gamemode
    gamescope
    vkd3d
    lsfg-vk-ui
    kdePackages.partitionmanager
    gnome-disk-utility
    timeshift
    bleachbit
    fastfetch
    inxi
    rsync
    pv
    zenity
    btrfs-progs
    pkgs.e2fsprogs
    pkgs.ntfs3g
    fwupd
    p7zip
    unrar
    unzip
    git
    wget
    curl
    mc
    vim
    patch
    stdenv.cc
    gcc
    clang
    llvm
    gnumake
    cmake
    meson
    ninja
    pkg-config
    binutils
    coreutils
  ];

  programs.gamemode.enable = pkgs.lib.mkForce true;

  programs.gamescope = {
    enable = pkgs.lib.mkForce true;
    capSysNice = false;
  };

  services.envfs.enable = pkgs.lib.mkForce true;
  services.swapspace.enable = pkgs.lib.mkForce true;
  services.fwupd.enable = pkgs.lib.mkForce true;
  services.printing.enable = pkgs.lib.mkForce false;
  services.openssh.enable = pkgs.lib.mkForce false;

  networking.firewall.allowedTCPPorts = [ 22 ];

  virtualisation.libvirtd.enable = pkgs.lib.mkForce true;
  programs.virt-manager.enable = pkgs.lib.mkForce true;
  virtualisation.spiceUSBRedirection.enable = pkgs.lib.mkForce true;
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

  users.groups.libvirtd.members = [ "__INSTALL_USER__" ];

  programs.zsh = {
    enable = pkgs.lib.mkForce true;
    enableCompletion = pkgs.lib.mkForce true;
    autosuggestions.enable = pkgs.lib.mkForce true;
    syntaxHighlighting.enable = pkgs.lib.mkForce true;
    enableLsColors = pkgs.lib.mkForce true;
    histSize = 30000;
    ohMyZsh = {
      enable = pkgs.lib.mkForce true;
      plugins = [ "git" "sudo" ];
    };
    promptInit = ''
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
    '';
  };

  fonts.packages = with pkgs; [
    nerd-fonts.meslo-lg
  ];

  users.users."__INSTALL_USER__".shell = pkgs.lib.mkForce pkgs.zsh;

  services.flatpak.enable = pkgs.lib.mkForce true;

  programs.appimage = {
    enable = pkgs.lib.mkForce true;
    binfmt = pkgs.lib.mkForce true;
  };

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
  # --- install.sh: END ---
NIXMODULE_EOF
sed -i "s/__INSTALL_USER__/$CURRENT_USER/g" "$BLOCK_TMP"

sudo sed -i '/install\.sh: BEGIN/,/install\.sh: END/d' "$CONF"
while IFS= read -r BLOCK_KEY; do
    sudo sed -i -E "/^[[:space:]]*${BLOCK_KEY//./\\.}[[:space:]]*=.*;[[:space:]]*$/d" "$CONF"
done < <(grep -E '^  [A-Za-z0-9_.-]+ = .*;$' "$BLOCK_TMP" | sed -E 's/^  ([A-Za-z0-9_.-]+) = .*/\1/')

LAST_BRACE_LINE="$(grep -n '^}' "$CONF" | tail -n 1 | cut -d: -f1)"
if [[ -z "$LAST_BRACE_LINE" ]]; then
    rm -f "$BLOCK_TMP"
    log_err "Nie znaleziono końca konfiguracji (}) w $CONF." \
            "Could not find the closing brace (}) in $CONF."
    exit 1
fi
sudo sed -i "$((LAST_BRACE_LINE - 1))r $BLOCK_TMP" "$CONF"
rm -f "$BLOCK_TMP"

# ==========================================================
# 3. PRZEBUDOWA SYSTEMU
# ==========================================================
show_progress 3 $TOTAL_STEPS "$MSG_REBUILD"

if ! sudo nixos-rebuild switch; then
    sudo cp -af "$BACKUP" "$CONF"
    log_err "Przebudowa systemu nie powiodła się. Przywrócono configuration.nix z kopii: $BACKUP" \
            "System rebuild failed. configuration.nix restored from backup: $BACKUP"
    exit 1
fi

ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" \
        ipv4.dns "1.1.1.2,1.0.0.2" \
        ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002" || true
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
sudo flatpak update --appstream || true
flatpak info com.github.tchx84.Flatseal &>/dev/null || sudo flatpak install -y flathub com.github.tchx84.Flatseal || true
flatpak info it.mijorus.gearlever &>/dev/null || sudo flatpak install -y flathub it.mijorus.gearlever || true

dconf load /org/virt-manager/virt-manager/ <<'EOF' || true
[/]
manager-window-height=297
manager-window-width=478
xmleditor-enabled=true

[confirm]
delete-storage=false
forcepoweroff=false

[connections]
autoconnect=['qemu:///system']
uris=['qemu:///system']

[conns/qemu:system]
window-size=(800, 600)

[details]
show-toolbar=true

[new-vm]
cpu-default='host-passthrough'
firmware='uefi'
graphics-type='spice'
storage-format='raw'

[stats]
enable-disk-poll=true
enable-memory-poll=true
enable-net-poll=true

[vmlist-fields]
disk-usage=false
network-traffic=false
EOF

show_progress 4 $TOTAL_STEPS "$MSG_REBUILD"

# ==========================================================
# 5. ZAKOŃCZENIE
# ==========================================================
show_progress 5 $TOTAL_STEPS "$MSG_FINALIZE"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

# =============================================================
#  RESTART SYSTEMU
# =============================================================
if [[ "$SCRIPT_LANG" == "pl" ]]; then
    RESTART_PROMPT="Czy chcesz teraz zrestartować system? [T/N]: "
else
    RESTART_PROMPT="Do you want to restart the system now? [Y/N]: "
fi
echo -en "${INFO}==> ${RESTART_PROMPT}${NC}" >&3
read -r RESTART_CHOICE < /dev/tty
case "$RESTART_CHOICE" in
    [YyTt]*)
        DO_REBOOT=1
        ;;
esac
exit 0
