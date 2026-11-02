#!/bin/bash
# Hooks of modules/system.toml, run by lib/hook.sh.

# Enables the multilib repository in the pacman configuration.
_enable_multilib() {
    local conf="/etc/pacman.conf"
    if grep -q "^\[multilib\]" "$conf"; then
        log_warn "Multilib is already enabled."
        return 0
    fi

    log_info "Enabling the multilib repository in pacman.conf..."
    sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' "$conf"
    sudo pacman -Sy --noconfirm
}

# Enables multilib on x86_64 (it does not exist for ARM), then updates the
# keyring and all system packages to their latest versions.
update_system() {
    if ! is_arm; then
        _enable_multilib
    fi

    local keyring="archlinux-keyring"
    if is_arm; then
        keyring="archlinuxarm-keyring"
    fi

    log_info "Updating $keyring..."
    yes | sudo pacman -Sy --needed "$keyring"

    log_info "Updating system packages..."
    yes | sudo pacman -Su
}

# Builds and installs the yay AUR helper from source.
install_yay() {
    if command -v yay &> /dev/null; then
        log_warn "yay is already installed."
        return 0
    fi

    log_info "Building yay from the AUR..."
    local build_dir="${XDG_CACHE_HOME:-$HOME/.cache}/yay-build"
    rm -rf "$build_dir"

    git clone https://aur.archlinux.org/yay.git "$build_dir"
    cd "$build_dir" || exit
    makepkg -si --noconfirm

    cd / || exit
    rm -rf "$build_dir"
}

# Sets the timezone when one is given, enables NTP synchronization and sets
# the hardware clock from the system time.
#
# Inputs: INPUT_ZONE (empty keeps the current timezone).
setup_timezone() {
    if [ -n "${INPUT_ZONE-}" ]; then
        if ! timedatectl list-timezones | grep -Fxq "$INPUT_ZONE"; then
            log_error "Unknown timezone: $INPUT_ZONE"
            return 1
        fi
        log_info "Setting the timezone to $INPUT_ZONE..."
        sudo timedatectl set-timezone "$INPUT_ZONE"
    fi

    log_info "Enabling NTP synchronization..."
    sudo timedatectl set-ntp true
    # Some ARM boards have no hardware clock
    sudo hwclock --systohc || log_warn "No hardware clock to set."
}
