#!/usr/bin/env bash

set -Eeuo pipefail
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/usr/sbin:/sbin:$PATH"

detect_system_lang() {
    local sys_lang="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    sys_lang="${sys_lang//\"/}"
    sys_lang="${sys_lang//\'/}"
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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="/etc/nixos"
CONFIG="$NIXOS_DIR/configuration.nix"
MODULE="$NIXOS_DIR/secureboot.nix"
FLAKE="$NIXOS_DIR/flake.nix"
FLAKE_LOCK="$NIXOS_DIR/flake.lock"
LANZABOOTE_REF="v1.0.0"
PKI_BUNDLE="/var/lib/sbctl"

MODULE_CREATED=0
FLAKE_CREATED=0
SUDO_KEEPALIVE_PID=""
DO_REBOOT=0

cleanup_on_exit() {
    local exit_code=$?
    trap - ERR
    if [ "$exit_code" -ne 0 ]; then
        if [ "$FLAKE_CREATED" = "1" ]; then
            sudo rm -f "$FLAKE" "$FLAKE_LOCK" 2>/dev/null || true
        fi
        if [ "$MODULE_CREATED" = "1" ]; then
            sudo rm -f "$MODULE" 2>/dev/null || true
        fi
    fi
    if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    if [ "$exit_code" -ne 0 ]; then
        sudo -k 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code).${NC}" >&2
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code).${NC}" >&2
        fi
    elif [ "$DO_REBOOT" = "1" ]; then
        sudo systemctl reboot
    else
        sudo -k 2>/dev/null || true
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ ERROR: $m${NC}" >&2; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

ask_yes_no() {
    local prompt_pl="$1" prompt_en="$2" choice=""
    echo -en "${INFO}==> $(_pick_msg "$prompt_pl" "$prompt_en")${NC}"
    if [[ -r /dev/tty ]]; then
        read -r choice < /dev/tty || return 1
    else
        read -r choice || return 1
    fi
    case "$choice" in
        [YyTt]*) return 0 ;;
        *) return 1 ;;
    esac
}

if [[ "$EUID" -eq 0 ]]; then
    log_err "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo." "Do not run this script as root. Run it as a regular user with sudo."
    exit 1
fi

command -v sudo >/dev/null 2>&1 || { log_err "Brak polecenia sudo." "sudo command not found."; exit 1; }
[ -d /sys/firmware/efi ] || { log_err "System nie działa w trybie UEFI." "The system is not running in UEFI mode."; exit 1; }
[ -f "$CONFIG" ] || { log_err "Brak pliku $CONFIG" "File $CONFIG not found"; exit 1; }
command -v nixos-rebuild >/dev/null 2>&1 || { log_err "To nie jest system NixOS." "This is not a NixOS system."; exit 1; }

sudo -v

(
    set +e
    trap - ERR
    while kill -0 "$$" 2>/dev/null; do
        sleep 50
        kill -0 "$$" 2>/dev/null || exit 0
        sudo -n -v 2>/dev/null || exit 0
    done
) </dev/null >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID=$!

NIXOS_VERSION="$(nixos-version)"
case "$NIXOS_VERSION" in
    *pre*) NIXPKGS_REF="nixos-unstable" ;;
    *) NIXPKGS_REF="nixos-$(echo "$NIXOS_VERSION" | cut -d. -f1,2)" ;;
esac

case "$(uname -m)" in
    x86_64)  SYSTEM_ARCH="x86_64-linux" ;;
    aarch64) SYSTEM_ARCH="aarch64-linux" ;;
    *)       SYSTEM_ARCH="$(uname -m)-linux" ;;
esac
HOST_NAME="$(hostname)"

export NIX_CONFIG="experimental-features = nix-command flakes"
SUDO_NIX=(sudo env "NIX_CONFIG=$NIX_CONFIG")

if [ ! -f "$MODULE" ]; then
    log_info "Tworzenie modułu $MODULE..." "Creating module $MODULE..."
    if [ -f "$SCRIPT_DIR/secureboot.nix" ]; then
        sudo install -m 0644 -o root -g root "$SCRIPT_DIR/secureboot.nix" "$MODULE"
    else
        sudo tee "$MODULE" > /dev/null <<EOF
{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.sbctl ];

  nix.settings.experimental-features = lib.mkDefault [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "$PKI_BUNDLE";
    configurationLimit = lib.mkDefault config.boot.loader.systemd-boot.configurationLimit;
  };
}
EOF
    fi
    MODULE_CREATED=1
fi

if ! sudo test -f "$PKI_BUNDLE/keys/PK/PK.key" || ! sudo test -f "$PKI_BUNDLE/keys/db/db.key"; then
    log_info "Generowanie kluczy Secure Boot..." "Generating Secure Boot keys..."
    if "${SUDO_NIX[@]}" nix shell "github:NixOS/nixpkgs/$NIXPKGS_REF#sbctl" --command sbctl create-keys --help 2>&1 | grep -q -- '--database-path'; then
        "${SUDO_NIX[@]}" nix shell "github:NixOS/nixpkgs/$NIXPKGS_REF#sbctl" --command sbctl create-keys --database-path "$PKI_BUNDLE" --export "$PKI_BUNDLE/keys"
    else
        "${SUDO_NIX[@]}" nix shell "github:NixOS/nixpkgs/$NIXPKGS_REF#sbctl" --command sbctl create-keys
    fi
    if ! sudo test -f "$PKI_BUNDLE/keys/PK/PK.key" || ! sudo test -f "$PKI_BUNDLE/keys/db/db.key"; then
        log_err "Klucze nie zostały utworzone w $PKI_BUNDLE/keys." "Keys were not created in $PKI_BUNDLE/keys."
        exit 1
    fi
fi

if [ ! -f "$FLAKE" ]; then
    log_info "Tworzenie stałego pliku $FLAKE..." "Creating permanent $FLAKE..."
    sudo tee "$FLAKE" > /dev/null <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/$NIXPKGS_REF";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/$LANZABOOTE_REF";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, lanzaboote, ... }: {
    nixosConfigurations."$HOST_NAME" = nixpkgs.lib.nixosSystem {
      modules = [
        { nixpkgs.hostPlatform = nixpkgs.lib.mkDefault "$SYSTEM_ARCH"; }
        ./configuration.nix
        lanzaboote.nixosModules.lanzaboote
        ./secureboot.nix
      ];
    };
  };
}
EOF
    FLAKE_CREATED=1
elif ! grep -q 'lanzaboote' "$FLAKE" || ! grep -q 'secureboot\.nix' "$FLAKE"; then
    MODULE_CREATED=0
    log_warn "Wykryto istniejący plik $FLAKE bez konfiguracji lanzaboote." "Found an existing $FLAKE without lanzaboote configuration."
    log_info "Utworzono $MODULE i wygenerowano klucze w $PKI_BUNDLE. Dodaj ręcznie wejście 'lanzaboote' oraz moduły 'lanzaboote.nixosModules.lanzaboote' i './secureboot.nix' do $FLAKE, a następnie uruchom skrypt ponownie." \
             "Created $MODULE and generated keys in $PKI_BUNDLE. Manually add the 'lanzaboote' input along with 'lanzaboote.nixosModules.lanzaboote' and './secureboot.nix' to $FLAKE, then run this script again."
    exit 0
fi

log_info "Przebudowa systemu z flake $FLAKE..." "Rebuilding the system with flake $FLAKE..."
"${SUDO_NIX[@]}" nixos-rebuild switch --flake "$NIXOS_DIR#$HOST_NAME"
MODULE_CREATED=0
FLAKE_CREATED=0

log_info "Weryfikacja podpisów..." "Verifying signatures..."
sudo sbctl verify || true

SB_STATUS="$(sudo env LC_ALL=C sbctl status 2>/dev/null || true)"
if grep -qi 'Setup Mode.*Enabled' <<< "$SB_STATUS"; then
    if ask_yes_no "Tryb Setup Mode jest aktywny. Zarejestrować klucze (z kluczami Microsoft)? [T/N]: " "Setup Mode is active. Enroll the keys (with Microsoft keys)? [Y/N]: "; then
        sudo sbctl enroll-keys --microsoft
    fi
elif grep -qi 'Secure Boot.*Enabled' <<< "$SB_STATUS"; then
    log_ok "Secure Boot jest już włączony – pomijam rejestrację kluczy." "Secure Boot is already enabled - skipping key enrollment."
else
    log_warn "Tryb Setup Mode jest wyłączony. Jeśli klucze sbctl nie zostały jeszcze zarejestrowane, wejdź do UEFI, wyczyść klucze Secure Boot (Setup Mode) i uruchom skrypt ponownie." "Setup Mode is disabled. If sbctl keys have not been enrolled yet, enter UEFI, clear the Secure Boot keys (Setup Mode) and run the script again."
fi

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!" "CONFIGURATION COMPLETED SUCCESSFULLY!"

if ask_yes_no "Czy chcesz teraz zrestartować system? [T/N]: " "Do you want to restart the system now? [Y/N]: "; then
    DO_REBOOT=1
fi
exit 0
