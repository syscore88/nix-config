#!/bin/bash

set -Eeuo pipefail
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/usr/sbin:/sbin:$PATH"

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl* ]]; then
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

NIXOS_DIR="/etc/nixos"
CONFIG="$NIXOS_DIR/configuration.nix"
MODULE="$NIXOS_DIR/secureboot.nix"
LANZABOOTE_REF="v1.0.0"
PKI_BUNDLE="/var/lib/sbctl"
CONFIG_BACKUP="$CONFIG.bak-secureboot"

CONFIG_CHANGED=0
TMP_DIR=""
SUDO_KEEPALIVE_PID=""
DO_REBOOT=0

cleanup_on_exit() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ] && [ "$CONFIG_CHANGED" = "1" ] && sudo test -f "$CONFIG_BACKUP"; then
        if sudo cp "$CONFIG_BACKUP" "$CONFIG"; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}⚠ Przywrócono oryginalny $CONFIG.${NC}"
            else
                echo -e "${WARN}⚠ Restored the original $CONFIG.${NC}"
            fi
        fi
    fi
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
    if [ "$exit_code" -ne 0 ]; then
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code).${NC}"
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code).${NC}"
        fi
    elif [ "$DO_REBOOT" = "1" ]; then
        sudo systemctl reboot
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

ask_yes_no() {
    local prompt_pl="$1" prompt_en="$2" choice
    echo -en "${INFO}==> $(_pick_msg "$prompt_pl" "$prompt_en")${NC}"
    read -r choice < /dev/tty
    case "$choice" in
        [YyTt]*) return 0 ;;
        *) return 1 ;;
    esac
}

if [[ "$EUID" -eq 0 ]]; then
    log_err "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo." "Do not run this script as root. Run it as a regular user with sudo."
    exit 1
fi

[ -d /sys/firmware/efi ] || { log_err "System nie działa w trybie UEFI." "The system is not running in UEFI mode."; exit 1; }
[ -f "$CONFIG" ] || { log_err "Brak pliku $CONFIG" "File $CONFIG not found"; exit 1; }
command -v nixos-rebuild >/dev/null 2>&1 || { log_err "To nie jest system NixOS." "This is not a NixOS system."; exit 1; }

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

NIXOS_VERSION="$(nixos-version)"
case "$NIXOS_VERSION" in
    *pre*) NIXPKGS_REF="nixos-unstable" ;;
    *) NIXPKGS_REF="nixos-$(echo "$NIXOS_VERSION" | cut -d. -f1,2)" ;;
esac

export NIX_CONFIG="experimental-features = nix-command flakes"
SUDO_NIX=(sudo env "NIX_CONFIG=$NIX_CONFIG")

if [ ! -f "$MODULE" ]; then
    log_info "Tworzenie modułu $MODULE..." "Creating module $MODULE..."
    sudo tee "$MODULE" > /dev/null <<EOF
{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.sbctl ];

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "$PKI_BUNDLE";
    configurationLimit = config.boot.loader.systemd-boot.configurationLimit;
  };
}
EOF
fi

if ! grep -q 'secureboot\.nix' "$CONFIG"; then
    log_info "Dodawanie modułu do $CONFIG..." "Adding the module to $CONFIG..."
    sudo cp "$CONFIG" "$CONFIG_BACKUP"
    CONFIG_CHANGED=1
    if grep -Eq '^[[:space:]]*imports[[:space:]]*=[[:space:]]*\[' "$CONFIG"; then
        sudo sed -i -E '0,/^[[:space:]]*imports[[:space:]]*=[[:space:]]*\[/s//&\n    .\/secureboot.nix/' "$CONFIG"
    elif grep -Eq '^[[:space:]]*imports[[:space:]]*=' "$CONFIG"; then
        sudo sed -i -E '/^[[:space:]]*imports[[:space:]]*=/,/\[/s/\[/[ .\/secureboot.nix/' "$CONFIG"
    else
        LINE="$(grep -nE '^\{[[:space:]]*$' "$CONFIG" | head -n1 | cut -d: -f1 || true)"
        [ -n "$LINE" ] || { log_err "Nie znaleziono miejsca na imports w $CONFIG" "Could not find a place for imports in $CONFIG"; exit 1; }
        sudo sed -i "${LINE}a\\  imports = [ ./secureboot.nix ];" "$CONFIG"
    fi
fi

if ! sudo test -f "$PKI_BUNDLE/keys/PK/PK.key"; then
    log_info "Generowanie kluczy Secure Boot..." "Generating Secure Boot keys..."
    "${SUDO_NIX[@]}" nix shell "github:NixOS/nixpkgs/$NIXPKGS_REF#sbctl" --command sbctl create-keys
fi

TMP_DIR="$(mktemp -d)"

cat > "$TMP_DIR/flake.nix" <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/$NIXPKGS_REF";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/$LANZABOOTE_REF";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, lanzaboote, ... }: {
    nixosConfigurations.secureboot = nixpkgs.lib.nixosSystem {
      modules = [
        $CONFIG
        lanzaboote.nixosModules.lanzaboote
      ];
    };
  };
}
EOF

log_info "Przebudowa systemu z tymczasowym flake..." "Rebuilding the system with a temporary flake..."
"${SUDO_NIX[@]}" nixos-rebuild switch --flake "$TMP_DIR#secureboot" --impure
CONFIG_CHANGED=0

log_info "Weryfikacja podpisów..." "Verifying signatures..."
sudo sbctl verify || true

SB_STATUS="$(sudo sbctl status 2>/dev/null || true)"
if grep -qi 'Setup Mode.*Enabled' <<< "$SB_STATUS"; then
    if ask_yes_no "Tryb Setup Mode jest aktywny. Zarejestrować klucze (z kluczami Microsoft)? [T/N]: " "Setup Mode is active. Enroll the keys (with Microsoft keys)? [Y/N]: "; then
        sudo sbctl enroll-keys --microsoft
    fi
else
    log_warn "Tryb Setup Mode jest wyłączony. Wejdź do UEFI, wyczyść klucze Secure Boot (Setup Mode) i uruchom skrypt ponownie, aby zarejestrować klucze." "Setup Mode is disabled. Enter UEFI, clear the Secure Boot keys (Setup Mode) and run the script again to enroll the keys."
fi

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!" "CONFIGURATION COMPLETED SUCCESSFULLY!"

if ask_yes_no "Czy chcesz teraz zrestartować system? [T/N]: " "Do you want to restart the system now? [Y/N]: "; then
    DO_REBOOT=1
fi
exit 0
