#!/bin/bash

# Enables the multilib repository in the pacman configuration.
_enable_multilib() {
    local conf="/etc/pacman.conf"
    log_info "Enabling multilib repository in pacman.conf..."

    if ! grep -q "^\[multilib\]" "$conf"; then
        log_info "Uncommenting [multilib] section..."
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' "$conf"
        sudo pacman -Sy --noconfirm
        log_info "Multilib enabled successfully."
    else
        log_info "Multilib is already enabled."
    fi
}

# Updates all system packages to their latest versions.
_update_system() {
    log_info "Updating system packages..."
    yes | sudo pacman -Syu
}

# Installs essential base system packages and utilities.
_install_system_packages() {
    local base_pkgs=(
        "base-devel"
		"openssl"
		"zlib"
		"xz"
		"tk"
        "git"
        "curl"
        "wget"
        "vim"
        "tree"
		"zsh"
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
        log_info "yay is already installed."
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
    log_info "yay installed successfully."
}

# Entry point for the system module.
setup() {
    run_task "Enable multilib" _enable_multilib
    run_task "Update system" _update_system
    run_task "Install system packages" _install_system_packages
    run_task "Install yay" _install_yay
}
