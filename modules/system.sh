#!/bin/bash

module "Base system"

# Enables the multilib repository in the pacman configuration.
_enable_multilib() {
    local conf="/etc/pacman.conf"
    log_info "Enabling multilib repository in pacman.conf..."

    if ! grep -q "^\[multilib\]" "$conf"; then
        log_info "Uncommenting [multilib] section..."
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' "$conf"
        sudo pacman -Sy --noconfirm
    else
        log_warn "Multilib is already enabled."
    fi
}

# Enables the multilib repository on x86_64 (it does not exist for ARM), then
# updates the keyring and all system packages to their latest versions.
_update_system() {
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

# Installs the base packages the other blocks rely on (build tools, git,
# download tools, OpenSSL, OpenSSH for the SSH key and agent, compression
# libraries) and a few everyday utilities.
_install_system_packages() {
    local base_pkgs=(
        "base-devel"
        "git"
        "curl"
        "wget"
        "openssl"
        "openssh"
        "zlib"
        "xz"
        "tree"
        "ncdu"
    )

    log_info "Installing base system packages..."
    for pkg in "${base_pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Builds and installs the yay AUR helper from source.
_install_yay() {
    log_info "Checking for AUR helper (yay)..."
    if command -v yay &>/dev/null; then
        log_warn "yay is already installed."
        return
    fi

    log_info "Installing yay..."
    local build_dir="/tmp/yay-build"
    rm -rf "$build_dir"

    git clone https://aur.archlinux.org/yay.git "$build_dir"
    cd "$build_dir" || exit
    makepkg -si --noconfirm

    cd "$HOME" || exit
    rm -rf "$build_dir"
}

# Always run, before the other blocks: they all need an up-to-date system,
# the base packages and yay. Each one needs the previous one, which orders
# them.
block system      _update_system           "multilib (x86_64), keyring and full system update" --required
block system.base _install_system_packages "Base packages (base-devel, git, curl, wget, openssl, openssh, tree, ncdu)" --required \
    --needs system
block system.yay  _install_yay             "yay AUR helper" --required \
    --needs system.base
