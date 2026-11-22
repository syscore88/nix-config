#!/usr/bin/env bash
set -uo pipefail

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
WARN='\033[1;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/update-log.XXXXXX)"
LOG_FILE="$HOME/update_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

RESTART_NEEDED=false
CURRENT_USER=$(whoami)
USE_RUN0=0
ELEVATE="sudo"
PRIVS_GRANTED=0
SUDO_KEEPALIVE_PID=""
RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
NIXOS_DIR="/etc/nixos"
KEEP_GENERATIONS=2

if command -v run0 >/dev/null 2>&1 && { ! command -v sudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; }; then
    USE_RUN0=1
    ELEVATE="run0"
fi

remove_temp_privs() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
    if [[ "$PRIVS_GRANTED" -eq 1 ]]; then
        if [[ "$USE_RUN0" -eq 1 ]]; then
            run0 rm -f "$RUN0_NOPASSWD_FILE" 2>/dev/null || true
            run0 systemctl try-restart polkit 2>/dev/null || true
        else
            sudo -k 2>/dev/null || true
        fi
        PRIVS_GRANTED=0
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    remove_temp_privs
    printf '\033[?25h' >&3 2>/dev/null || true
    echo "" >&3 2>/dev/null || true
    if [ "$exit_code" -ne 0 ]; then
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}[X] Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3 2>/dev/null || true
        else
            echo -e "${ERR}[X] An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3 2>/dev/null || true
        fi
    else
        rm -f "$LOG_FILE"
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

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ "$filled" -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ "$empty" -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    if (( avail >= 4 )); then
        if (( ${#msg} > avail )); then
            msg="${msg:0:$((avail - 3))}..."
        fi
        printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
    else
        printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%%" "$bar_filled" "$bar_empty" "$percent" >&3
    fi
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
    MSG_UPDATE_FAIL="[X] Aktualizacja źródeł NixOS nie powiodła się – przerywam."
    MSG_REBUILD_FAIL="[X] Przebudowa systemu NixOS nie powiodła się – przerywam."
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
    MSG_UPDATE_FAIL="[X] NixOS source update failed - aborting."
    MSG_REBUILD_FAIL="[X] NixOS system rebuild failed - aborting."
fi

echo -e "${INFO}======================================================${NC}" >&3
echo -e "${INFO}${MSG_TITLE}${NC}" >&3
echo -e "${INFO}======================================================${NC}" >&3

if [[ "$USE_RUN0" -eq 1 ]]; then
    POLKIT_DIR_REAL="$(readlink -f /etc/polkit-1/rules.d 2>/dev/null || true)"
    if [[ -n "$POLKIT_DIR_REAL" && "$POLKIT_DIR_REAL" != /nix/store/* ]]; then
        POLKIT_TMP="$(mktemp)"
        cat > "$POLKIT_TMP" << EOF
polkit.addRule(function(action, subject) {
    if (subject.user == "$CURRENT_USER") {
        return polkit.Result.YES;
    }
});
EOF
        if { [[ -r /dev/tty ]] && run0 install -m 0644 -o root -g root "$POLKIT_TMP" "$RUN0_NOPASSWD_FILE" </dev/tty >&3 2>&3; } \
           || { [[ ! -r /dev/tty ]] && run0 install -m 0644 -o root -g root "$POLKIT_TMP" "$RUN0_NOPASSWD_FILE" >&3 2>&3; }; then
            PRIVS_GRANTED=1
            run0 systemctl try-restart polkit 2>/dev/null || true
            rm -f "$POLKIT_TMP"
        else
            rm -f "$POLKIT_TMP"
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}[X] Nieprawidłowe hasło lub nie udało się nadać uprawnień tymczasowych (run0) – przerywam.${NC}" >&3
            else
                echo -e "${ERR}[X] Wrong password or failed to grant temporary privileges (run0) - aborting.${NC}" >&3
            fi
            exit 1
        fi
    else
        if ! { { [[ -r /dev/tty ]] && run0 true </dev/tty >&3 2>&3; } || { [[ ! -r /dev/tty ]] && run0 true >&3 2>&3; }; }; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}[X] Nie udało się uzyskać uprawnień administratora (run0) – przerywam.${NC}" >&3
            else
                echo -e "${ERR}[X] Failed to obtain administrator privileges (run0) - aborting.${NC}" >&3
            fi
            exit 1
        fi
    fi
else
    echo -e "${WARN}${MSG_ASK_PASS}${NC}" >&3
    if [[ -r /dev/tty ]]; then
        IFS= read -rs SUDO_PASSWORD < /dev/tty || true
    else
        IFS= read -rs SUDO_PASSWORD || true
    fi
    echo "" >&3

    if printf '%s\n' "${SUDO_PASSWORD:-}" | sudo -S -p '' -v &>/dev/null; then
        unset SUDO_PASSWORD
        PRIVS_GRANTED=1
        if ! sudo -n true 2>/dev/null; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}[X] Sesja sudo nie została zapamiętana (sprawdź ustawienie timestamp_timeout w sudoers) – przerywam.${NC}" >&3
            else
                echo -e "${ERR}[X] Sudo session was not cached (check timestamp_timeout in sudoers) - aborting.${NC}" >&3
            fi
            exit 1
        fi
        (
            while kill -0 "$$" 2>/dev/null; do
                sleep 50
                sudo -n -v 2>/dev/null || exit 0
            done
        ) </dev/null >/dev/null 2>&1 &
        SUDO_KEEPALIVE_PID=$!
    else
        unset SUDO_PASSWORD
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}[X] Nieprawidłowe hasło administratora – przerywam. Jeśli w /etc/sudoers działa opcja targetpw, podaj hasło roota.${NC}" >&3
        else
            echo -e "${ERR}[X] Wrong administrator password - aborting. If targetpw is set in /etc/sudoers, enter the root password.${NC}" >&3
        fi
        exit 1
    fi
fi

TOTAL_STEPS=16
STEP=0
printf '\033[?25l' >&3
show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

# ---------------------------------------------------------------
# PHASE: UPDATE
# ---------------------------------------------------------------
USE_FLAKE=false
[[ -f "$NIXOS_DIR/flake.nix" ]] && USE_FLAKE=true

if [ "$USE_FLAKE" = true ]; then
    "$ELEVATE" env LC_ALL=C nix --extra-experimental-features 'nix-command flakes' flake update --flake "$NIXOS_DIR" \
        || "$ELEVATE" env LC_ALL=C nix --extra-experimental-features 'nix-command flakes' flake update "$NIXOS_DIR"
else
    "$ELEVATE" env LC_ALL=C nix-channel --update
fi
UPDATE_RC=$?
if [ "$UPDATE_RC" -ne 0 ]; then
    printf "\r\033[K" >&3
    echo -e "${ERR}${MSG_UPDATE_FAIL}${NC}" >&3
    exit "$UPDATE_RC"
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

BEFORE_SYSTEM="$(readlink -f /run/current-system)"

if [ "$USE_FLAKE" = true ]; then
    "$ELEVATE" env LC_ALL=C nixos-rebuild switch --flake "$NIXOS_DIR"
else
    "$ELEVATE" env LC_ALL=C nixos-rebuild switch
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

if command -v gext &> /dev/null; then
    gext update
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

if command -v cinnamon-spice-updater &> /dev/null; then
    cinnamon-spice-updater --update-all
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_UPDATE"

if command -v fwupdmgr &> /dev/null; then
    "$ELEVATE" env LC_ALL=C fwupdmgr refresh --force
    FWUPD_OUT=$("$ELEVATE" env LC_ALL=C fwupdmgr update -y --no-reboot-check 2>&1)
    echo "$FWUPD_OUT"
    if echo "$FWUPD_OUT" | grep -qiE "restart|reboot"; then
        RESTART_NEEDED=true
    fi
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

# ---------------------------------------------------------------
# PHASE: SYSTEM CLEANUP (SUDO)
# ---------------------------------------------------------------
"$ELEVATE" nix-env --profile /nix/var/nix/profiles/system --delete-generations "+$KEEP_GENERATIONS"
nix-env --delete-generations "+$KEEP_GENERATIONS" 2>/dev/null || true
"$ELEVATE" /run/current-system/bin/switch-to-configuration boot
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

"$ELEVATE" nix-collect-garbage
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

if command -v flatpak &> /dev/null; then
    FLATPAK_BEFORE=$(flatpak list --system --app --columns=application,version 2>/dev/null)

    "$ELEVATE" flatpak update --system -y

    FLATPAK_AFTER=$(flatpak list --system --app --columns=application,version 2>/dev/null)

    FLATPAK_PKGS=$(LC_ALL=C join -t$'\t' -j1 \
        <(echo "$FLATPAK_BEFORE" | LC_ALL=C sort -t$'\t' -k1,1) \
        <(echo "$FLATPAK_AFTER" | LC_ALL=C sort -t$'\t' -k1,1) 2>/dev/null \
        | awk -F'\t' '$2 != $3 { printf "%s: %s → %s\n", $1, ($2==""?"?":$2), ($3==""?"?":$3) }')
    print_pkg_list "$MSG_FLATPAK_UPDATED" "$FLATPAK_PKGS"

    "$ELEVATE" flatpak uninstall --unused --system --delete-data -y
    "$ELEVATE" flatpak repair --system

    USED_REMOTES=$(flatpak list --system --columns=origin 2>/dev/null | sort -u)
    ALL_REMOTES=$(flatpak remotes --system --columns=name 2>/dev/null)
    while IFS= read -r remote; do
        if [ -n "$remote" ] && [ "$remote" != "flathub" ] && ! echo "$USED_REMOTES" | grep -qxF -- "$remote"; then
            "$ELEVATE" flatpak remote-delete --system --force "$remote" 2>/dev/null
        fi
    done <<< "$ALL_REMOTES"

    "$ELEVATE" rm -rf /var/tmp/flatpak-cache-* 2>/dev/null
    "$ELEVATE" rm -rf /var/lib/flatpak/repo/tmp/* 2>/dev/null
    "$ELEVATE" find /var/lib/flatpak -name "*.tmp" -delete 2>/dev/null
    "$ELEVATE" rm -f /var/lib/flatpak/history 2>/dev/null
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

"$ELEVATE" journalctl --vacuum-time=7d
"$ELEVATE" find /var/log -type f -name "*.gz" -mtime +7 -exec rm -f {} +
"$ELEVATE" find /var/log -type f -name "*.1" -exec rm -f {} +
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

"$ELEVATE" find /tmp -xdev -type f -atime +3 \
    ! -path "/tmp/systemd-private-*" \
    ! -path "/tmp/.*" \
    -exec rm -f {} + 2>/dev/null
"$ELEVATE" find /var/tmp -xdev -type f -atime +3 \
    ! -path "/var/tmp/systemd-private-*" \
    ! -path "/var/tmp/.*" \
    -exec rm -f {} + 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

# ---------------------------------------------------------------
# PHASE: USER CLEANUP (NO SUDO)
# ---------------------------------------------------------------
if command -v flatpak &> /dev/null; then
    FLATPAK_BEFORE=$(flatpak list --user --app --columns=application,version 2>/dev/null)

    flatpak update --user -y

    FLATPAK_AFTER=$(flatpak list --user --app --columns=application,version 2>/dev/null)

    FLATPAK_PKGS=$(LC_ALL=C join -t$'\t' -j1 \
        <(echo "$FLATPAK_BEFORE" | LC_ALL=C sort -t$'\t' -k1,1) \
        <(echo "$FLATPAK_AFTER" | LC_ALL=C sort -t$'\t' -k1,1) 2>/dev/null \
        | awk -F'\t' '$2 != $3 { printf "%s: %s → %s\n", $1, ($2==""?"?":$2), ($3==""?"?":$3) }')
    print_pkg_list "$MSG_FLATPAK_UPDATED" "$FLATPAK_PKGS"

    flatpak uninstall --unused --user --delete-data -y
    flatpak repair --user
    rm -rf ~/.local/share/flatpak/repo/tmp/* 2>/dev/null
    rm -f ~/.local/share/flatpak/history 2>/dev/null

    INSTALLED_FLATPAKS=$(flatpak list --app --columns=application 2>/dev/null)
    if [ -n "$INSTALLED_FLATPAKS" ] && [ -d "$HOME/.var/app" ]; then
        for app_dir in "$HOME/.var/app"/*; do
            if [ -d "$app_dir" ]; then
                app_id=$(basename "$app_dir")
                if ! echo "$INSTALLED_FLATPAKS" | grep -qxF -- "$app_id"; then
                    rm -rf "$app_dir"
                fi
            fi
        done
    fi
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

find ~/.cache -type f -atime +14 \
    ! -path "*/mozilla/*" \
    ! -path "*/google-chrome/*" \
    ! -path "*/chromium/*" \
    ! -path "*/BraveSoftware/*" \
    ! -path "*/opera/*" \
    ! -path "*/vivaldi/*" \
    ! -path "*/huggingface/*" \
    ! -path "*/torch/*" \
    ! -path "*/ms-playwright/*" \
    -exec rm -f {} + 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

find ~/.cache/thumbnails -type f -atime +7 -exec rm -f {} + 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

fc-cache -r
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

USER_ID=$(id -u)
if command -v dconf &> /dev/null && [ -S "/run/user/$USER_ID/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" dconf reset /org/virt-manager/virt-manager/urls/isos 2>/dev/null
fi
rm -rf "$HOME/.cache/virt-manager" 2>/dev/null
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

# ---------------------------------------------------------------
# PHASE: RESTART CHECK
# ---------------------------------------------------------------
if [ -d /run/booted-system ] && [ -d /run/current-system ]; then
    for part in initrd kernel kernel-modules; do
        booted_target="$(readlink -f "/run/booted-system/$part" 2>/dev/null || true)"
        current_target="$(readlink -f "/run/current-system/$part" 2>/dev/null || true)"
        if [ -n "$booted_target" ] && [ -n "$current_target" ] && [ "$booted_target" != "$current_target" ]; then
            RESTART_NEEDED=true
        fi
    done
fi
STEP=$((STEP+1)); show_progress $STEP $TOTAL_STEPS "$MSG_PHASE_CLEAN_SYS"

remove_temp_privs

printf '\033[?25h' >&3 2>/dev/null || true
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
if [[ -r /dev/tty ]]; then
    read -r < /dev/tty || true
else
    read -r || true
fi
