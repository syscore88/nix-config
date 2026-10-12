# ❄️ NixOS Post-Install Setup Script

A comprehensive, automated Bash post-installation script for **NixOS**. Instead of changing the system imperatively, it injects a managed block of declarative settings into `/etc/nixos/configuration.nix`, rebuilds the system, and then sets up Flatpak apps and your dotfiles. It configures graphics, DNS, a silent boot splash, garbage collection, a large curated set of system/multimedia/gaming/virtualization packages, and more.

The script auto-detects the system language (Polish/English) from the `LANG`/`LC_ALL` locale and prints all status messages accordingly.

---

## 🚀 Script Features

- **Safe Configuration Handling**: Before touching anything, it creates a timestamped backup of `configuration.nix` (`configuration.nix.bak-<timestamp>`). If `nixos-rebuild switch` fails, the backup is restored automatically.
- **Idempotent Managed Block**: All settings are written between `install.sh: BEGIN` / `install.sh: END` markers just before the closing `}` of `configuration.nix`. Re-running the script replaces the previous block instead of duplicating it.
- **Graphics & Desktop Basics**: Enables `hardware.graphics` with 32-bit support, `dconf`, `geoclue2`, Bluetooth, and `cdemu`, and adds NTFS/exFAT/Btrfs filesystem support.
- **DNS Configuration**: Sets Cloudflare security DNS (`1.1.1.2`/`1.0.0.2` + IPv6) both as system nameservers and as NetworkManager nameservers.
- **Silent Boot Splash**: Enables Plymouth with the `bgrt` theme, quiet kernel parameters (`quiet splash udev.log_level=3 ...`), reduced console log level, and a 0-second boot loader timeout.
- **Generation & Garbage Collection Limits**: Keeps at most 2 `systemd-boot` generations and runs daily `nix.gc` with `--delete-generations +2`.
- **Package Installation**: Declares a large curated `environment.systemPackages` set covering browsers (Brave, Chrome, Firefox), office/media apps (LibreOffice, GIMP, Krita, Kdenlive, Audacity, VLC, Mixxx...), communication (Discord, Telegram), gaming/Proton stack (`wine-staging`, `winetricks`, `gamemode`, `gamescope`, `mangohud`, `vkd3d`, `faugus-launcher`, `lsfg-vk-ui`, `steam-run`), system utilities, and dev tools (`git`, `gcc`, `clang`, `cmake`, `meson`, `ninja`...).
- **Virtualization**: Enables `libvirtd`, `virt-manager`, SPICE USB redirection and `polkit`, and adds the current user to the `libvirtd` group.
- **Flatpak**: Enables the Flatpak service, adds the Flathub remote, and installs Flatseal and Gear Lever.
- **Dotfiles & Config Copy**: Copies optional `.local` and `.config` directories from the script folder into the user's home directory.
- **Temporary Sudo Keep-Alive**: Requests the admin password once at the start and keeps the sudo session alive in the background for the duration of the script.
- **Progress Bar & Logging**: Displays a live progress bar across 5 steps. On failure, a detailed log is saved to `~/install_error_<timestamp>.log`.
- **Automatic Reboot**: After a successful run, the system is rebooted automatically.

---

## 🔍 Module Details

### 1. Checks & Permissions
Verifies the script is **not** run as root, that the system is NixOS (`ID=nixos`), and that `/etc/nixos/configuration.nix` exists. Then it asks for the sudo password and starts a background keep-alive.

### 2. Dotfiles Copy
Copies the optional `.local` and `.config` directories from the script folder into `~/.local` and `~/.config`, overwriting existing files.

### 3. configuration.nix Update
Creates a backup, removes any block left by a previous run, and inserts the new managed block before the final closing brace of `configuration.nix`.

### 4. System Rebuild
Runs `nixos-rebuild switch`. On failure, `configuration.nix` is restored from the backup and the script exits with an error.

### 5. Flatpak Apps & Finalization
Adds the Flathub remote, updates appstream data, installs Flatseal and Gear Lever (if missing), prints the summary, and reboots the system.

---

## 🚀 How to Run
```bash
   nix-shell -p git
 ```

1. Clone the repository to your disk
   ```bash
   git clone https://github.com/syscore88/nix-config.git
   ```

2. Navigate to the folder
   ```bash
   cd nix-config
   ```

3. Make the script executable
   ```bash
   chmod +x install.sh
   ```

4. Run the script
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
- The following optional folders, placed alongside `install-nixos.sh`, are picked up automatically if present: `.local/`, `.config/`.
- The script **installs a large number of packages** (development, multimedia, gaming, and full KVM/QEMU virtualization stacks) — review the `environment.systemPackages` list in the script before running if you want a lighter setup.
- The boot settings (`boot.loader.systemd-boot.configurationLimit`, Plymouth, kernel parameters) assume a `systemd-boot` setup.
- Settings placed in the managed block may conflict with the same options already defined elsewhere in your configuration; remove duplicates before running.
- The system reboots automatically after a successful run.
- On failure, check the generated `install_error_<timestamp>.log` file in your home directory for details.
