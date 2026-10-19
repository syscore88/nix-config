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

MODULES=(boot kernel memory hardware cdemu network nix system flatpak gaming virtualisation security shell desktop packages)
MODULES_DIR="$NIXOS_DIR/modules"

FOUND_MODULES=()
for MODULE in "${MODULES[@]}"; do
    if [[ -f "$SCRIPT_DIR/$MODULE.nix" ]]; then
        FOUND_MODULES+=("$MODULE")
    else
        echo "Skipping missing file $MODULE.nix."
    fi
done

if ! sudo grep -q 'hardware-configuration\.nix' "$CONF"; then
    log_err "Nie znaleziono listy imports w $CONF." \
            "Could not find the imports list in $CONF."
    exit 1
fi

BACKUP="$CONF.bak-$(date +%Y%m%d_%H%M%S)"
sudo cp -a "$CONF" "$BACKUP"

sudo mkdir -p "$MODULES_DIR"
for MODULE in "${FOUND_MODULES[@]}"; do
    sed "s/__INSTALL_USER__/$CURRENT_USER/g" "$SCRIPT_DIR/$MODULE.nix" | sudo tee "$MODULES_DIR/$MODULE.nix" > /dev/null
    sudo chmod 644 "$MODULES_DIR/$MODULE.nix"
done

sudo sed -i '/install\.sh: BEGIN/,/install\.sh: END/d' "$CONF"
while IFS= read -r BLOCK_KEY; do
    sudo sed -i -E "/^[[:space:]]*${BLOCK_KEY//./\\.}[[:space:]]*=.*;[[:space:]]*$/d" "$CONF"
done < <(for MODULE in "${FOUND_MODULES[@]}"; do cat "$MODULES_DIR/$MODULE.nix"; done | grep -E '^  [A-Za-z0-9_.-]+ = .*;$' | sed -E 's/^  ([A-Za-z0-9_.-]+) = .*/\1/')

for MODULE in "${FOUND_MODULES[@]}"; do
    if ! sudo grep -qF "./modules/$MODULE.nix" "$CONF"; then
        sudo sed -i "0,/hardware-configuration\.nix/s|hardware-configuration\.nix|&\n    ./modules/$MODULE.nix|" "$CONF"
    fi
done

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

show_progress 4 $TOTAL_STEPS "$MSG_REBUILD"

# ==========================================================
# 4. ZAKOŃCZENIE
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
