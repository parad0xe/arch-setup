#!/bin/bash
# The machine: architecture, virtualization, packages, services, boot loader
# and initramfs. The system files can be moved for the tests.

GRUB_DEFAULT_FILE="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
GRUB_CFG_FILE="${GRUB_CFG_FILE:-/boot/grub/grub.cfg}"
LOADER_ENTRIES_DIR="${LOADER_ENTRIES_DIR:-/boot/loader/entries}"
MKINITCPIO_CONF="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"

# Prints the machine architecture (x86_64, aarch64).
machine_arch() {
    uname -m
}

# Returns success on a 64-bit ARM CPU (e.g. Apple Silicon with Asahi Linux),
# whose repositories (Arch Linux ARM) lack some x86_64 packages.
is_arm() {
    [ "$(uname -m)" = "aarch64" ]
}

# Returns success on a 64-bit x86 CPU.
is_x86_64() {
    [ "$(uname -m)" = "x86_64" ]
}

# Returns success on an Apple Silicon Mac (Asahi Linux), whose device tree
# declares the apple,arm-platform compatible.
is_apple_silicon() {
    grep -qa 'apple,arm-platform' /proc/device-tree/compatible 2> /dev/null
}

# Returns success inside a virtual machine.
in_vm() {
    systemd-detect-virt --vm --quiet
}

# Prints the CPU vendor: intel, amd, or nothing when it is neither.
cpu_vendor() {
    case "$(awk -F': *' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo 2> /dev/null)" in
        GenuineIntel) echo intel ;;
        AuthenticAMD) echo amd ;;
    esac
}

# ==========================================
# PACKAGES AND SERVICES
# ==========================================

# Returns success when a package is installed.
#
# Args:
#   pkg: The package name.
pkg_installed() {
    pacman -Qq "$1" > /dev/null 2>&1
}

# Installs packages from the repositories; the ones already installed are
# left as they are.
#
# Args:
#   ...: The package names.
install_pkg() {
    log_info "Installing: $*"
    sudo pacman -S --needed --noconfirm "$@"
}

# Installs packages from the AUR with yay; the ones already installed are
# left as they are.
#
# Args:
#   ...: The package names.
install_aur_pkg() {
    log_info "Installing from the AUR: $*"
    yay -S --needed --noconfirm "$@"
}

# Enables a systemd unit at boot, and starts it with --now.
#
# Args:
#   unit: The unit name.
#   ...: Options of systemctl enable (e.g. --now).
enable_service() {
    log_info "Enabling $1..."
    sudo systemctl enable "${@:2}" "$1"
}

# ==========================================
# BOOT
# ==========================================

# Prints the boot loader in use: grub, systemd-boot, or nothing when it is
# neither.
boot_loader() {
    if [ -f "$GRUB_DEFAULT_FILE" ] && command -v grub-mkconfig > /dev/null; then
        echo grub
    elif [ -d "$LOADER_ENTRIES_DIR" ]; then
        echo systemd-boot
    fi
}

# Adds a parameter to the kernel command line: in GRUB's default command
# line, then regenerates its menu, or in every systemd-boot entry. Warns
# when the boot loader is unknown.
#
# Args:
#   param: The parameter (e.g. nvidia_drm.modeset=1).
kernel_cmdline_add() {
    local param="$1" entry changed=0
    case "$(boot_loader)" in
        grub)
            if grep -qF -- "$param" "$GRUB_DEFAULT_FILE"; then
                log_info "GRUB already has $param."
                return 0
            fi
            log_info "Adding $param to the GRUB command line..."
            if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT_FILE"; then
                sudo sed -i "s/^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"/\1 $param\"/" "$GRUB_DEFAULT_FILE"
            else
                echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$param\"" | sudo tee -a "$GRUB_DEFAULT_FILE" > /dev/null
            fi
            if ! grep -qF -- "$param" "$GRUB_DEFAULT_FILE"; then
                log_warn "GRUB_CMDLINE_LINUX_DEFAULT is not double-quoted in $GRUB_DEFAULT_FILE: add $param to it yourself."
                return 0
            fi
            log_info "Regenerating the GRUB menu..."
            sudo grub-mkconfig -o "$GRUB_CFG_FILE"
            ;;
        systemd-boot)
            for entry in "$LOADER_ENTRIES_DIR"/*.conf; do
                if [ ! -f "$entry" ] || grep -Eq "^options( .*)? $param( |$)" "$entry"; then
                    continue
                fi
                log_info "Adding $param to the boot entry ${entry##*/}..."
                sudo sed -i "s/^\(options .*\)$/\1 $param/" "$entry"
                changed=1
            done
            if [ "$changed" -eq 0 ]; then
                log_info "The boot entries already have $param."
            fi
            ;;
        *)
            log_warn "Unknown boot loader: add $param to the kernel command line yourself."
            ;;
    esac
}

# Prints the MODULES line of mkinitcpio.conf, or nothing when there is none.
_mkinitcpio_modules_line() {
    grep -E '^MODULES=\(' "$MKINITCPIO_CONF" | tail -n 1 || true
}

# Prints the kernel modules, among the given ones, that the MODULES of
# mkinitcpio.conf do not load yet.
#
# Args:
#   ...: The module names.
mkinitcpio_missing_modules() {
    local current mod
    current=$(_mkinitcpio_modules_line)
    current="${current#MODULES=(}"
    current="${current%)}"
    for mod in "$@"; do
        if [[ " $current " != *" $mod "* ]]; then
            echo "$mod"
        fi
    done
}

# Adds kernel modules to the MODULES of mkinitcpio.conf, the ones already
# there left as they are (the caller rebuilds the initramfs when
# mkinitcpio_missing_modules listed some).
#
# Args:
#   ...: The module names.
mkinitcpio_add_modules() {
    local line current missing
    missing=$(mkinitcpio_missing_modules "$@" | tr '\n' ' ')
    missing="${missing% }"
    if [ -z "$missing" ]; then
        log_info "mkinitcpio already loads $*."
        return 0
    fi

    line=$(_mkinitcpio_modules_line)
    current="${line#MODULES=(}"
    current="${current%)}"
    local new="MODULES=(${current:+$current }$missing)"
    log_info "Loading $missing early (mkinitcpio)..."
    if [ -n "$line" ]; then
        sudo sed -i "s/^MODULES=(.*)/$new/" "$MKINITCPIO_CONF"
    else
        echo "$new" | sudo tee -a "$MKINITCPIO_CONF" > /dev/null
    fi
}

# ==========================================
# SYSTEM FILES
# ==========================================

# Adds a line to a system file when it is missing. With a key (a regex
# naming the line, e.g. the mount point of an fstab entry), a line that
# matches it is replaced instead of kept next to the new one: a run can be
# repeated, and an entry corrected.
#
# Args:
#   file: The file, written with sudo.
#   line: The line.
#   key: The regex of the line to replace (optional).
ensure_line() {
    local file="$1" line="$2" key="${3-}"
    if sudo grep -qxF -- "$line" "$file" 2> /dev/null; then
        return 0
    fi
    if [ -n "$key" ] && sudo grep -qE -- "$key" "$file" 2> /dev/null; then
        log_info "Replacing the line matching $key in $file..."
        sudo sed -i -E "\#${key}#d" "$file"
    fi
    log_info "Adding to $file: $line"
    printf '%s\n' "$line" | sudo tee -a "$file" > /dev/null
}
