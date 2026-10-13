#!/usr/bin/env bash
set -uo pipefail

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
WARN='\033[1;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/update-log.XXXXXX)"
LOG_FILE="$HOME/update_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

RESTART_NEEDED=false
KERNEL_UPDATED=false
USE_RUN0=0
PRIVS_GRANTED=0
RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
NIXOS_DIR="/etc/nixos"
KEEP_GENERATIONS=2

remove_temp_privs() {
    [[ "$PRIVS_GRANTED" -eq 1 ]] || return 0
    if [[ "$USE_RUN0" -eq 1 ]]; then
        sudo -n rm -f "$RUN0_NOPASSWD_FILE" 2>/dev/null
        sudo -n systemctl try-restart polkit 2>/dev/null || true
    else
        sudo -n rm -f /etc/sudoers.d/99-temp-update 2>/dev/null
    fi
    PRIVS_GRANTED=0
}

cleanup_on_exit() {
    local exit_code=$?
    remove_temp_privs
    printf '\033[?25h' >&3
    echo "" >&3
    if [ "$exit_code" -ne 0 ]; then
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

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

print_pkg_list() {
    local title="$1"
    local list="$2"
    [ -z "$list" ] && return
    printf "\r\033[K" >&3
    echo -e "${INFO}${title}${NC}" >&3
    while IFS= read -r pkg; do
        [ -n "$pkg" ] && echo -e "  ${SUCCESS}•${NC} $pkg" >&3
    done <<< "$list"
}

if [ "$SCRIPT_LANG" = "pl" ]; then
    MSG_TITLE="                  KONSERWACJA SYSTEMU                  "
    MSG_ASK_PASS="Proszę podać hasło administratora (sudo):"
    MSG_PHASE_UPDATE="[1/2] Aktualizacja i optymalizacja..."
    MSG_PKGS_UPDATED="Aktualizowane pakiety:"
    MSG_PKGS_NONE="Brak pakietów do aktualizacji (system aktualny)."
    MSG_FLATPAK_UPDATED="Aktualizowane pakiety Flatpak:"
    MSG_PHASE_CLEAN_SYS="[2/2] Czyszczenie systemowe..."
    MSG_DONE="             KONSERWACJA SYSTEMU ZAKOŃCZONA!           "
    MSG_RESTART_WARN="UWAGA: Zalecany jest restart komputera"
    MSG_NO_RESTART="Restart systemu nie jest aktualnie wymagany."
    MSG_PRESS_ENTER="Naciśnij Enter, aby zamknąć okno..."
    MSG_REBUILD_FAIL="✘ Przebudowa systemu NixOS nie powiodła się – przerywam."
else
    MSG_TITLE="                   SYSTEM MAINTENANCE                   "
    MSG_ASK_PASS="Please enter the administrator (sudo) password:"
    MSG_PHASE_UPDATE="[1/2] Updates and optimization..."
    MSG_PKGS_UPDATED="Updating packages:"
    MSG_PKGS_NONE="No packages to update (system is up to date)."
    MSG_FLATPAK_UPDATED="Updating Flatpak packages:"
    MSG_PHASE_CLEAN_SYS="[2/2] System cleanup..."
    MSG_DONE="             SYSTEM MAINTENANCE COMPLETE!           "
    MSG_RESTART_WARN="WARNING: A system restart is recommended"
    MSG_NO_RESTART="A system restart is not currently required."
    MSG_PRESS_ENTER="Press Enter to close this window..."
    MSG_REBUILD_FAIL="✘ NixOS system rebuild failed - aborting."
fi

CURRENT_USER=$(whoami)
if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

echo -e "${INFO}======================================================${NC}" >&3
echo -e "${INFO}${MSG_TITLE}${NC}" >&3
echo -e "${INFO}======================================================${NC}" >&3
echo -e "${WARN}${MSG_ASK_PASS}${NC}" >&3
if [[ -r /dev/tty ]]; then
    IFS= read -rs SUDO_PASSWORD < /dev/tty || true
else
    IFS= read -rs SUDO_PASSWORD || true
fi
echo "" >&3

if [[ "$USE_RUN0" -eq 1 ]]; then
    POLKIT_TMP="$(mktemp)"
    cat > "$POLKIT_TMP" << EOF
polkit.addRule(function(action, subject) {
    if (subject.user == "$CURRENT_USER") {
        return polkit.Result.YES;
    }
});
EOF
    if printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' install -m 0644 -o root -g root "$POLKIT_TMP" "$RUN0_NOPASSWD_FILE" &>/dev/null; then
        PRIVS_GRANTED=1
        printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' systemctl try-restart polkit 2>/dev/null || true
        if ! sudo -n true 2>/dev/null; then
            printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' systemctl try-restart polkit 2>/dev/null || true
        fi
        rm -f "$POLKIT_TMP"
        unset SUDO_PASSWORD
    else
        rm -f "$POLKIT_TMP"
        unset SUDO_PASSWORD
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Nieprawidłowe hasło lub nie udało się nadać uprawnień tymczasowych – przerywam. Jeśli w /etc/sudoers działa opcja targetpw, podaj hasło roota.${NC}" >&3
        else
            echo -e "${ERR}✘ Wrong password or failed to grant temporary privileges - aborting. If targetpw is set in /etc/sudoers, enter the root password.${NC}" >&3
        fi
        exit 1
    fi
else
    SUDOERS_TMP="$(mktemp)"
    SUDO_ERR="$(mktemp)"
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$CURRENT_USER" > "$SUDOERS_TMP"
    VISUDO_BIN="$(command -v visudo 2>/dev/null || echo /run/current-system/sw/bin/visudo)"
    if printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' "$VISUDO_BIN" -cf "$SUDOERS_TMP" >/dev/null 2>>"$SUDO_ERR" \
       && printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' install -d -m 0750 -o root -g root /etc/sudoers.d >/dev/null 2>>"$SUDO_ERR" \
       && printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-update >/dev/null 2>>"$SUDO_ERR"; then
        PRIVS_GRANTED=1
        rm -f "$SUDOERS_TMP" "$SUDO_ERR"
        unset SUDO_PASSWORD
        if ! sudo -n true 2>/dev/null; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}⚠ Reguła NOPASSWD zainstalowana, ale sudo nadal prosi o hasło - sprawdź 'sudo -l' (możliwa inna reguła w /etc/sudoers nadpisująca wpis z sudoers.d).${NC}" >&3
            else
                echo -e "${WARN}⚠ NOPASSWD rule installed, but sudo still asks for a password - check 'sudo -l' (a rule in /etc/sudoers may be overriding the sudoers.d entry).${NC}" >&3
            fi
        fi
    else
        cat "$SUDO_ERR"
        rm -f "$SUDOERS_TMP" "$SUDO_ERR"
        unset SUDO_PASSWORD
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Nieprawidłowe hasło lub składnia pliku sudoers – przerywam. Jeśli w /etc/sudoers działa opcja targetpw, podaj hasło roota.${NC}" >&3
        else
            echo -e "${ERR}✘ Wrong password or invalid sudoers syntax - aborting. If targetpw is set in /etc/sudoers, enter the root password.${NC}" >&3
        fi
        exit 1
    fi
fi

if ! sudo -n true 2>/dev/null; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}✘ Nie udało się uzyskać uprawnień bez hasła – przerywam.${NC}" >&3
    else
        echo -e "${ERR}✘ Could not obtain passwordless privileges - aborting.${NC}" >&3
    fi
    exit 1
fi

TOTAL_STEPS=15
STEP=0
show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

# ---------------------------------------------------------------
# PHASE: UPDATE
# ---------------------------------------------------------------
USE_FLAKE=false
[[ -f "$NIXOS_DIR/flake.nix" ]] && USE_FLAKE=true

if [ "$USE_FLAKE" = true ]; then
    sudo env LC_ALL=C nix flake update --flake "$NIXOS_DIR" \
        || sudo env LC_ALL=C nix flake update "$NIXOS_DIR"
else
    sudo env LC_ALL=C nix-channel --update
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

BEFORE_SYSTEM="$(readlink -f /run/current-system)"

if [ "$USE_FLAKE" = true ]; then
    sudo env LC_ALL=C nixos-rebuild switch --flake "$NIXOS_DIR"
else
    sudo env LC_ALL=C nixos-rebuild switch
fi
REBUILD_RC=$?
if [ "$REBUILD_RC" -ne 0 ]; then
    printf "\r\033[K" >&3
    echo -e "${ERR}${MSG_REBUILD_FAIL}${NC}" >&3
    exit "$REBUILD_RC"
fi

AFTER_SYSTEM="$(readlink -f /run/current-system)"
PKG_VERSIONS=""
if [ "$BEFORE_SYSTEM" != "$AFTER_SYSTEM" ]; then
    PKG_VERSIONS=$(nix --extra-experimental-features nix-command store diff-closures "$BEFORE_SYSTEM" "$AFTER_SYSTEM" 2>/dev/null \
        | grep -E '→|∅' | sed -E 's/, [-+][0-9.]+ [KMG]iB$//' | sort -u)
fi

if [ -n "$PKG_VERSIONS" ]; then
    print_pkg_list "$MSG_PKGS_UPDATED" "$PKG_VERSIONS"
else
    printf "\r\033[K" >&3
    echo -e "${INFO}${MSG_PKGS_NONE}${NC}" >&3
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

if command -v fwupdmgr &> /dev/null; then
    sudo fwupdmgr refresh --force
    FWUPD_OUT=$(sudo fwupdmgr update -y 2>&1)
    echo "$FWUPD_OUT"
    if echo "$FWUPD_OUT" | grep -qiE "restart|reboot"; then
        RESTART_NEEDED=true
    fi
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

# ---------------------------------------------------------------
# PHASE: SYSTEM CLEANUP (SUDO)
# ---------------------------------------------------------------
sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations "+$KEEP_GENERATIONS"
sudo /run/current-system/bin/switch-to-configuration boot
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

sudo nix-collect-garbage
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

if command -v flatpak &> /dev/null; then
    FLATPAK_BEFORE=$(flatpak list --system --app --columns=application,version 2>/dev/null)

    sudo flatpak update --system -y

    FLATPAK_AFTER=$(flatpak list --system --app --columns=application,version 2>/dev/null)

    FLATPAK_PKGS=$(join -t$'\t' -j1 \
        <(echo "$FLATPAK_BEFORE" | sort -t$'\t' -k1,1) \
        <(echo "$FLATPAK_AFTER" | sort -t$'\t' -k1,1) 2>/dev/null \
        | awk -F'\t' '$2 != $3 { printf "%s: %s → %s\n", $1, ($2==""?"?":$2), ($3==""?"?":$3) }')
    print_pkg_list "$MSG_FLATPAK_UPDATED" "$FLATPAK_PKGS"

    sudo flatpak uninstall --unused --system --delete-data -y
    sudo flatpak repair --system

    USED_REMOTES=$(flatpak list --columns=origin 2>/dev/null | sort -u)
    ALL_REMOTES=$(flatpak remotes --columns=name 2>/dev/null)
    while IFS= read -r remote; do
        if [ -n "$remote" ] && ! echo "$USED_REMOTES" | grep -qx "$remote"; then
            sudo flatpak remote-delete --force "$remote" 2>/dev/null
        fi
    done <<< "$ALL_REMOTES"

    sudo rm -rf /var/tmp/flatpak-cache-* 2>/dev/null
    sudo rm -rf /var/lib/flatpak/repo/tmp/* 2>/dev/null
    sudo find /var/lib/flatpak -name "*.tmp" -delete 2>/dev/null
    sudo rm -f /var/lib/flatpak/history 2>/dev/null
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

sudo journalctl --vacuum-time=7d
sudo find /var/log -type f -name "*.gz" -mtime +14 -exec rm -f {} +
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

sudo find /tmp -type f -atime +5 -exec rm -f {} + 2>/dev/null
sudo find /var/tmp -type f -atime +5 -exec rm -f {} + 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

# ---------------------------------------------------------------
# PHASE: USER CLEANUP (NO SUDO)
# ---------------------------------------------------------------
nix-env --delete-generations "+$KEEP_GENERATIONS" 2>/dev/null
nix-collect-garbage 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

if command -v flatpak &> /dev/null; then
    FLATPAK_BEFORE=$(flatpak list --user --app --columns=application,version 2>/dev/null)

    flatpak update --user -y

    FLATPAK_AFTER=$(flatpak list --user --app --columns=application,version 2>/dev/null)

    FLATPAK_PKGS=$(join -t$'\t' -j1 \
        <(echo "$FLATPAK_BEFORE" | sort -t$'\t' -k1,1) \
        <(echo "$FLATPAK_AFTER" | sort -t$'\t' -k1,1) 2>/dev/null \
        | awk -F'\t' '$2 != $3 { printf "%s: %s → %s\n", $1, ($2==""?"?":$2), ($3==""?"?":$3) }')
    print_pkg_list "$MSG_FLATPAK_UPDATED" "$FLATPAK_PKGS"

    flatpak uninstall --unused --user --delete-data -y
    flatpak repair --user
    rm -f ~/.local/share/flatpak/history 2>/dev/null
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

find ~/.cache -type f -atime +14 \
    ! -path "*/mozilla/*" \
    ! -path "*/google-chrome/*" \
    ! -path "*/chromium/*" \
    ! -path "*/BraveSoftware/*" \
    ! -path "*/opera/*" \
    ! -path "*/vivaldi/*" \
    -exec rm -f {} + 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

find ~/.cache/thumbnails -type f -atime +14 -exec rm -f {} + 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

fc-cache -r
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

USER_ID=$(id -u)
if [ -S "/run/user/$USER_ID/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" dconf reset /org/virt-manager/virt-manager/urls/isos 2>/dev/null
fi
rm -rf "$HOME/.cache/virt-manager" 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

# ---------------------------------------------------------------
# PHASE: RESTART CHECK
# ---------------------------------------------------------------
for part in initrd kernel kernel-modules; do
    if [ "$(readlink -f "/run/booted-system/$part" 2>/dev/null)" != "$(readlink -f "/run/current-system/$part" 2>/dev/null)" ]; then
        RESTART_NEEDED=true
        KERNEL_UPDATED=true
    fi
done
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

remove_temp_privs

echo -e "\n" >&3
echo -e "${SUCCESS}======================================================${NC}" >&3
echo -e "${SUCCESS}${MSG_DONE}${NC}" >&3
echo -e "${SUCCESS}======================================================${NC}" >&3

if [ "$RESTART_NEEDED" = true ]; then
    echo -e "${WARN}${MSG_RESTART_WARN}${NC}" >&3
else
    echo -e "${INFO}${MSG_NO_RESTART}${NC}" >&3
fi
echo -e "${WARN}${MSG_PRESS_ENTER}${NC}" >&3
read -r
