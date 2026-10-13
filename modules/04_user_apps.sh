#!/bin/bash

# Installs essential command-line tools and utilities.
_install_cli_tools() {
    local tools=(
        "fzf"
        "zoxide"
        "eza"
        "bat"
        "fastfetch"
		"wl-clipboard"
		"grim"
		"slurp"
		"satty"
		"playerctl"
		"libnotify"
		"rofi"
		"ffmpegthumbnailer"
		"awww"
		"brightnessctl"
		"pavucontrol"
		"starship"
		"zsh-autosuggestions"
		"zsh-syntax-highlighting"
		"krita"
    )

    log_info "Installing CLI tools..."
    for pkg in "${tools[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Installing Ghostty terminal..."
    install_aur_pkg "ghostty"

    log_info "Installing mpvpaper (video wallpapers)..."
    install_aur_pkg "mpvpaper"

    log_info "Installing wlogout (power menu)..."
    install_aur_pkg "wlogout"
}

# Installs Oh My Zsh framework for the Z shell.
_setup_zsh() {
    local base_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh"
    local script="$base_url/master/tools/install.sh"

    log_info "Checking for Oh My Zsh..."
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log_info "Installing Oh My Zsh..."
        RUNZSH=no CHSH=yes sh -c "$(curl -fsSL "$script")"
        log_info "Oh My Zsh installed successfully."
    else
        log_warn "Oh My Zsh is already installed."
    fi
}

# Installs user applications like the web browser and file manager.
_install_user_apps() {
    log_info "Installing web browser (Brave)..."
    install_aur_pkg "brave-bin"
    
	log_info "Installing jetbrains toolbox..."
    install_aur_pkg "jetbrains-toolbox"

    local fm_pkgs=(
		"discord"
        "thunar"
        "thunar-archive-plugin"
        "gvfs"
        "file-roller"
		"keepass"
		"network-manager-applet"
    )

    for pkg in "${fm_pkgs[@]}"; do
        install_pkg "$pkg"
    done

	fm_pkgs=(
		"yubico-authenticator-bin"
    )

    for pkg in "${fm_pkgs[@]}"; do
        install_aur_pkg "$pkg"
    done
}

setup() {
	run_task "Installing CLI Tools..." _install_cli_tools
    run_task "Installing Oh My Zsh..." _setup_zsh
    run_task "Installing Graphical Apps..." _install_user_apps
}
