#!/bin/bash

set -e

log_info() {
    echo -e "\n\033[1;34m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\n\033[1;31m[ERROR]\033[0m $1"
}

update_system() {
    log_info "Updating system packages..."
    sudo pacman -Syu --noconfirm
}

install_pkg() {
    log_info "Checking and installing: $1"
    sudo pacman -S --needed --noconfirm "$1"
}

install_yay() {
    log_info "Checking for AUR helper (yay)..."
    if command -v yay &> /dev/null; then
        echo "yay is already installed."
        return
    fi

    log_info "Installing yay..."
    local build_dir="/tmp/yay-build"
    rm -rf "$build_dir"

    git clone https://aur.archlinux.org/yay.git "$build_dir"
    cd "$build_dir"

    makepkg -si --noconfirm

    # Clean up
    cd "$HOME"
    rm -rf "$build_dir"
    log_info "yay installed successfully."
}

install_aur_pkg() {
    log_info "Checking and installing AUR package: $1"
    yay -S --needed --noconfirm "$1"
}

install_wayland_stack() {
    log_info "Installing the Wayland stack..."
    
    local wayland_pkgs=(
	"hyprland"
        "waybar"
        "sddm"
        "kitty"
        "wofi"
        "hyprpaper"
        "mako"
        "ttf-jetbrains-mono-nerd"
        "polkit-kde-agent"
        "qt5-wayland"
        "qt6-wayland"
        "qt5-graphicaleffects"
        "qt5-svg"
        "qt5-quickcontrols2"
    )

    for pkg in "${wayland_pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

setup_hyprlock() {
    log_info "Installing hyprlock..."
    install_pkg "hyprlock"
}

setup_sddm_theme() {
    log_info "Installing and configuring SDDM theme..."
    
    install_aur_pkg "sddm-sugar-dark"
    
    log_info "Applying theme to SDDM configuration..."
    sudo mkdir -p /etc/sddm.conf.d
    
    echo -e "[Theme]\nCurrent=sugar-dark" | sudo tee /etc/sddm.conf.d/theme.conf > /dev/null
}

enable_sddm() {
    log_info "Enabling SDDM systemd service..."
    sudo systemctl enable -f sddm.service
}

setup_essential_services() {
    log_info "Setting up audio (Pipewire) and networking..."

    local service_pkgs=(
        "networkmanager"
        "pipewire"
        "pipewire-alsa"
        "pipewire-pulse"
        "pipewire-jack"
        "wireplumber"
    )

    for pkg in "${service_pkgs[@]}"; do
        install_pkg "$pkg"
    done

    # Enable NetworkManager to start on boot
    sudo systemctl enable NetworkManager.service

    log_info "Essential services installed and enabled."
}

setup_bluetooth() {
    log_info "Setting up Bluetooth..."
    
    local bt_pkgs=(
        "bluez"
        "bluez-utils"
        "blueman"
    )

    for pkg in "${bt_pkgs[@]}"; do
        install_pkg "$pkg"
    done

    sudo systemctl enable bluetooth.service
    
    log_info "Bluetooth services installed and enabled."
}

enable_multilib() {
    log_info "Enabling multilib repository in pacman.conf..."
    
    local conf="/etc/pacman.conf"
    
    if grep -q "^\[multilib\]" "$conf"; then
        echo "Multilib is already enabled."
    else
        log_info "Uncommenting [multilib] section..."
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' "$conf"
        
        sudo pacman -Sy
        log_info "Multilib enabled successfully."
    fi
}

setup_nvidia() {
    log_info "Cleaning up any conflicting NVIDIA packages..."
    local conflict_pkgs=("nvidia" "nvidia-open")
    for pkg in "${conflict_pkgs[@]}"; do
        sudo pacman -R --noconfirm "$pkg" 2>/dev/null || true
    done

    log_info "Installing NVIDIA drivers for RTX 4090..."
    local nvidia_pkgs=(
        "linux-headers"
        "nvidia-dkms"
        "nvidia-utils"
        "lib32-nvidia-utils"
        "egl-wayland"
        "nvidia-settings"
    )

    for pkg in "${nvidia_pkgs[@]}"; do
        install_pkg "$pkg"
    done
    
    log_info "Configuring early module loading for NVIDIA..."
    sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P
    
    log_info "NVIDIA drivers installed."
}

setup_grub_nvidia() {
    log_info "Configuring GRUB for NVIDIA Wayland support..."

    local grub_file="/etc/default/grub"
    local param="nvidia_drm.modeset=1"

    if grep -q "$param" "$grub_file"; then
        echo "GRUB is already configured for NVIDIA DRM."
    else
        log_info "Adding $param to GRUB_CMDLINE_LINUX_DEFAULT..."
        sudo sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"/\1 $param\"/" "$grub_file"

        log_info "Regenerating GRUB configuration..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

link_config() {
    local src="$1"
    local dest="$2"

    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        log_info "Backing up existing $dest to ${dest}.bak"
        mv "$dest" "${dest}.bak"
    elif [ -L "$dest" ]; then
        rm "$dest"
    fi

    log_info "Linking $src to $dest"
    ln -s "$src" "$dest"
}

setup_dotfiles() {
    log_info "Setting up dotfiles (symlinks)..."

    local repo_dir
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_dir="$HOME/.config"

    link_config "$repo_dir/dotfiles/hypr" "$config_dir/hypr"
    link_config "$repo_dir/dotfiles/waybar" "$config_dir/waybar"
    link_config "$repo_dir/dotfiles/wofi" "$config_dir/wofi"

    link_config "$repo_dir/dotfiles/zshrc" "$HOME/.zshrc"
    link_config "$repo_dir/dotfiles/ghostty" "$config_dir/ghostty"

    log_info "Dotfiles linked successfully."
}

setup_cli_tools() {
    log_info "Installing CLI tools..."

    local tools=(
        "zsh"
        "fzf"
        "zoxide"
        "eza"
        "bat"
        "fastfetch"
    )

    for pkg in "${tools[@]}"; do
        install_pkg "$pkg"
    done
    
    install_aur_pkg "ghostty"
}

setup_zsh() {
    log_info "Setting up Oh My Zsh..."

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        RUNZSH=no CHSH=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        log_info "Oh My Zsh installed successfully."
    else
        echo "Oh My Zsh is already installed."
    fi
}

setup_user_apps() {
    log_info "Installing user applications..."
    
    install_aur_pkg "brave-bin"

    local fm_pkgs=(
        "thunar"
        "thunar-archive-plugin"
        "gvfs"
        "file-roller"
    )

    for pkg in "${fm_pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

setup_ssh_key() {
    local email="$1"
    local key_path="$HOME/.ssh/id_ed25519"
    
    log_info "Setting up SSH key for $email..."
    
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    if [ -f "$key_path" ]; then
        echo "SSH key already exists at $key_path."
    else
        ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""
        log_info "SSH key generated successfully."
    fi
}

setup_git() {
    local git_user="$1"
    local git_email="$2"

    log_info "Configuring global Git settings..."

    git config --global user.name "$git_user"
    git config --global user.email "$git_email"
    git config --global init.defaultBranch main

    log_info "Git successfully configured for $git_user."
}

main() {
    log_info "Starting the Arch Linux base setup..."
    
    enable_multilib
    update_system

    local base_pkgs=(
        "base-devel"
        "git"
        "curl"
        "wget"
	"vim"
    )

    for pkg in "${base_pkgs[@]}"; do
        install_pkg "$pkg"
    done


    install_yay

    # 1. Hardware and Services
    setup_essential_services
    setup_bluetooth
    setup_nvidia
    setup_grub_nvidia

    # 2. Graphical Environment
    install_wayland_stack
    setup_hyprlock
    setup_sddm_theme
    enable_sddm

    # 3. User Tools and Applications
    setup_cli_tools
    setup_zsh
    setup_user_apps
    
    setup_ssh_key "parad0xe@protonmail.com"
    setup_git "parad0xe" "parad0xe@protonmail.com"
    
    setup_dotfiles

    log_info "Installation and setup completed successfully!"
    log_info "Please reboot to apply changes."
}

main
