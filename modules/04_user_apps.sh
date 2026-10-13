#!/bin/bash

# Builds Ghostty from the AUR (ghostty-git) on ARM, where it is not packaged.
# Its PKGBUILD is fixed first:
#   - zig 0.16 extracts the fetched packages into zig-pkg/ in the sources
#     and only keeps their archives in the cache where the PKGBUILD looks;
#   - ncurses already ships the "ghostty" terminfo entry, so only
#     "xterm-ghostty" is packaged, like the official ghostty-terminfo.
_build_ghostty_git() {
    if command -v ghostty &>/dev/null; then
        log_warn "Ghostty is already installed."
        return
    fi

    # Provides pandoc-cli, a build dependency missing from the ARM repositories
    install_aur_pkg "pandoc-bin"

    local build_dir="$HOME/.cache/ghostty-git-build"
    rm -rf "$build_dir"

    git clone https://aur.archlinux.org/ghostty-git.git "$build_dir"
    cd "$build_dir" || exit

    sed -i 's|"$srcdir/zig-global-cache/p"|"$srcdir/$_pkgbase/zig-pkg"|' PKGBUILD
    sed -i 's|build/usr/share/terminfo/\*|build/usr/share/terminfo/x|' PKGBUILD
    makepkg -s --noconfirm

    # Installs the terminal and its dependencies, not the Nautilus extension
    local pkgs
    mapfile -t pkgs < <(makepkg --packagelist | grep -E '/ghostty-(shell-integration-|terminfo-)?git-[0-9]')
    sudo pacman -U --noconfirm "${pkgs[@]}"

    cd "$HOME" || exit
    rm -rf "$build_dir"
}

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
    if is_arm; then
        _build_ghostty_git
    else
        install_pkg "ghostty"
    fi

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

    local fm_pkgs=(
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
}

# Installs the applications only published for x86_64.
_install_x86_apps() {
	log_info "Installing jetbrains toolbox..."
    install_aur_pkg "jetbrains-toolbox"

    log_info "Installing Discord..."
    install_pkg "discord"

    log_info "Installing Yubico Authenticator..."
    install_aur_pkg "yubico-authenticator-bin"
}

setup() {
	run_task "Installing CLI Tools..." _install_cli_tools
    run_task "Installing Oh My Zsh..." _setup_zsh
    run_task "Installing Graphical Apps..." _install_user_apps

    if is_arm; then
        log_info "No ARM build of JetBrains Toolbox, Discord and Yubico Authenticator, skipping them."
    else
        run_task "Installing x86_64 Apps..." _install_x86_apps
    fi
}
