# ❄️ NixOS Post-Install Setup Script

A comprehensive, automated Bash post-installation script for **NixOS**. Instead of changing the system imperatively, it injects a managed block of declarative settings into `/etc/nixos/configuration.nix`, rebuilds the system, and then sets up Flatpak apps, virt-manager defaults and your dotfiles. It configures graphics, the XanMod kernel, DNS, a silent boot splash, performance tweaks, garbage collection, Zsh, a large curated set of system/multimedia/gaming/virtualization packages, and more.

The script auto-detects the system language (Polish/English) from the `LANG`/`LC_ALL` locale and prints all status messages accordingly.

---

## 🚀 Script Features

- **Safe Configuration Handling**: Before touching anything, it creates a timestamped backup of `configuration.nix` (`configuration.nix.bak-<timestamp>`). If `nixos-rebuild switch` fails, the backup is restored automatically.
- **Idempotent Managed Block**: All settings are written between `install.sh: BEGIN` / `install.sh: END` markers just before the closing `}` of `configuration.nix`. Re-running the script replaces the previous block instead of duplicating it.
- **Graphics & Desktop Basics**: Enables `hardware.graphics` with 32-bit support, `dconf`, `geoclue2`, Bluetooth, XDG portals (`xdgOpenUsePortal`), and adds NTFS/exFAT/Btrfs filesystem support.
- **XanMod Kernel**: Uses `linuxPackages_xanmod_latest` and loads the `ntsync` kernel module (useful for Wine/Proton).
- **CD/DVD Image Emulation (CDEmu)**: Installs `cdemu-daemon`, `cdemu-client`, `gcdemu` and `image-analyzer`, builds the `vhba` kernel module for the XanMod kernel, adds a udev rule for `/dev/vhba_ctl` (group `wheel`), registers the D-Bus service and defines a `cdemu-daemon` systemd user service.
- **DNS Configuration**: Sets Cloudflare security DNS (`1.1.1.2`/`1.0.0.2` + IPv6) through NetworkManager's global DNS configuration (`global-dns.conf`). After the rebuild, the same servers are also applied to the currently active NetworkManager connection via `nmcli`.
- **Silent Boot Splash**: Enables Plymouth with the `bgrt` theme, quiet kernel parameters (`quiet`, `splash`, `udev.log_level=3`, `systemd.show_status=auto`), reduced console log level, non-verbose initrd, and a 0-second boot loader timeout.
- **Performance & Gaming Tweaks**:
  - Kernel parameters: `nohibernate`, `usbcore.autosuspend=-1`, `mitigations=off`
  - `sysctl` tuning: `split_lock_mitigate`, `sched_cfs_bandwidth_slice_us`, `tcp_fin_timeout`, `vm.max_map_count`, `vm.swappiness`, `vm.vfs_cache_pressure`, dirty page limits and `vm.min_free_kbytes`
  - `zramSwap` with the `lz4` algorithm, plus `swapspace` (dynamic swap files)
  - `systemd` `DefaultTimeoutStopSec` set to 3 seconds
  - `boot.tmp.cleanOnBoot` enabled
  - `MESA_SHADER_CACHE_MAX_SIZE` set to 24G
  - `envfs` enabled (provides `/usr/bin` and other FHS paths for non-Nix binaries)
- **Generation & Garbage Collection Limits**: Keeps at most 2 `systemd-boot` generations and runs daily `nix.gc` with `--delete-generations +2`. Also enables `auto-optimise-store` and the `nix-command` experimental feature.
- **Package Installation**: Declares a large curated `environment.systemPackages` set covering:
  - **Browsers**: Brave, Google Chrome, Firefox
  - **Office & graphics**: LibreOffice (Qt) with Polish Hunspell dictionary, Ghostwriter, GIMP, Krita (+ G'MIC plugin)
  - **Multimedia**: Audacity, HandBrake, Kdenlive, SoundConverter, Mixxx, Qmmp, VLC
  - **Communication & downloads**: Discord, Telegram, qBittorrent
  - **Gaming / Proton stack**: `wine-staging`, `winetricks`, `gamemode`, `gamescope`, `mangohud`, `vkd3d`, `faugus-launcher`, `lsfg-vk-ui`, `steam-run` (with `programs.gamemode` and `programs.gamescope` enabled)
  - **Disc image tools**: `cdemu-daemon`, `cdemu-client`, `gcdemu`, `image-analyzer`
  - **System utilities**: KDE Partition Manager, GNOME Disk Utility, Timeshift, BleachBit, dconf-editor, fastfetch, inxi, rsync, pv, zenity, btrfs-progs, fwupd, p7zip, unrar, unzip, git, wget, curl, mc, vim, OpenCode
  - **Dev tools**: `gcc`, `clang`, `llvm`, `gnumake`, `cmake`, `meson`, `ninja`, `pkg-config`, `binutils`, `coreutils`, `patch`, `stdenv.cc`
- **Services**: Enables `fwupd` and disables `printing` and `openssh`. TCP port 22 is still added to the firewall's allowed ports.
- **Environment Variables**: Sets `EDITOR=nano`, `GTK_USE_PORTAL=1`, `OBS_VKCAPTURE_QUIET=1` and `MESA_SHADER_CACHE_MAX_SIZE=24G`.
- **Zsh Shell Setup**: Enables Zsh with completion, autosuggestions, syntax highlighting, LS colors, a 30000-entry history, Oh My Zsh (`git` and `sudo` plugins) and the Powerlevel10k prompt (sources `~/.p10k.zsh` if present), installs the MesloLGS Nerd Font, and sets Zsh as the current user's default shell.
- **Virtualization**: Enables `libvirtd`, `virt-manager`, SPICE USB redirection and `polkit`, and adds the current user to the `libvirtd` group. After the rebuild, sensible virt-manager defaults are loaded via `dconf` (autoconnect to `qemu:///system`, UEFI firmware, `host-passthrough` CPU, SPICE graphics, raw storage format, XML editor enabled).
- **Flatpak & AppImage**: Enables the Flatpak service, adds the Flathub remote, installs Flatseal and Gear Lever, and enables AppImage support with `binfmt` so AppImages can be run directly.
- **Unwanted Package Removal**: Excludes selected default desktop apps via:
  - `environment.plasma6.excludePackages`: Elisa, KWalletManager, Plasma Browser Integration, Plasma Vault, KRfb, Decibels (an overlay also removes the KWalletManager desktop entries)
  - `environment.gnome.excludePackages`: Calendar, Clocks, Music, User Docs, Contacts, Maps, Weather, Yelp, Evolution (+ EWS), Epiphany, Decibels, Rhythmbox, Showtime
  - `environment.xfce.excludePackages`: Parole
- **Dotfiles & Config Copy**: Copies the optional `.update.sh` file (to `~/.update.sh`, made executable) and the optional `.local` and `.config` directories from the script folder into the user's home directory.
- **Temporary Sudo Keep-Alive**: Requests the admin password once at the start and keeps the sudo session alive in the background for the duration of the script.
- **Progress Bar & Logging**: Displays a live progress bar across 5 steps. On failure, a detailed log is saved to `~/install_error_<timestamp>.log`.
- **Optional Reboot**: After a successful run, the script asks whether you want to restart the system now (`Y/N`, or `T/N` in Polish) and reboots only if you confirm.

---

## 🔍 Module Details

### 1. Checks & Permissions
Verifies the script is **not** run as root, that the system is NixOS (`ID=nixos`), and that `/etc/nixos/configuration.nix` exists. Then it asks for the sudo password and starts a background keep-alive.

### 2. Dotfiles Copy
Copies the optional `.update.sh` file to `~/.update.sh` and the optional `.local` and `.config` directories from the script folder into `~/.local` and `~/.config`, overwriting existing files.

### 3. configuration.nix Update
Creates a backup, removes any block left by a previous run, substitutes the current username into the new managed block (libvirt group, Zsh default shell), and inserts the block before the final closing brace of `configuration.nix`.

### 4. System Rebuild
Runs `nixos-rebuild switch`. On failure, `configuration.nix` is restored from the backup and the script exits with an error.

### 5. DNS, Flatpak, virt-manager & Finalization
Applies the Cloudflare security DNS servers to the active NetworkManager connection, adds the Flathub remote, updates appstream data, installs Flatseal and Gear Lever (if missing), loads the virt-manager `dconf` defaults, prints the summary and asks whether to reboot the system.

---

## 🚀 How to Run

1. If `git` is not available yet, open a temporary shell with it
   ```bash
   nix-shell -p git
   ```

2. Clone the repository to your disk
   ```bash
   git clone https://github.com/syscore88/nix-config.git
   ```

3. Navigate to the folder
   ```bash
   cd nix-config
   ```

4. Make the script executable
   ```bash
   chmod +x install.sh
   ```

5. Run the script
   > ⚠️ **IMPORTANT:** Run the script as a **regular user** (NOT as root/sudo). The script will ask for the administrator password at the start.
   ```bash
   ./install.sh
   ```

---

### ☕ Support the Project

If you find this tool helpful and it saved you some time, consider buying me a coffee to support further development!

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

---

If you find this project useful, leave a star! ⭐

---

## ⚠️ Requirements & Notes

- A working **NixOS** installation with a standard `/etc/nixos/configuration.nix` and an internet connection.
- `sudo` access for the current user.
- The following optional items, placed alongside `install.sh`, are picked up automatically if present: `.update.sh`, `.local/`, `.config/`.
- The script **installs a large number of packages** (development, multimedia, gaming, and full KVM/QEMU virtualization stacks) — review the `environment.systemPackages` list in the script before running if you want a lighter setup.
- The script switches to the **XanMod kernel** (`linuxPackages_xanmod_latest`), which is built/downloaded on the first rebuild and may take a while.
- The kernel parameter `mitigations=off` disables CPU vulnerability mitigations for better performance, which lowers security; remove it from the script if that is not acceptable for you.
- OpenSSH is disabled, but port 22 is still opened in the firewall; adjust this in the script if you do not need it.
- The script changes the default shell of the current user to **Zsh**; for the Powerlevel10k prompt to render correctly, set your terminal font to *MesloLGS Nerd Font*.
- The boot settings (`boot.loader.systemd-boot.configurationLimit`, Plymouth, kernel parameters) assume a `systemd-boot` setup.
- Settings placed in the managed block use `mkForce` for most options, but some (e.g. `environment.systemPackages`, `boot.kernelParams`, `boot.kernelModules`, `nix.settings`) may still conflict with the same options already defined elsewhere in your configuration; remove duplicates before running.
- After a successful run the script asks whether to reboot; a reboot is recommended so that the new kernel and boot settings take effect.
- On failure, check the generated `install_error_<timestamp>.log` file in your home directory for details.
