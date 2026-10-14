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

    log_info "Ghostty is not packaged for ARM, building it from the AUR (ghostty-git)..."

    log_info "Installing pandoc-bin (provides pandoc-cli, needed to build Ghostty)..."
    install_aur_pkg "pandoc-bin"

    local build_dir="$HOME/.cache/ghostty-git-build"
    rm -rf "$build_dir"

    log_info "Downloading the ghostty-git PKGBUILD..."
    git clone https://aur.archlinux.org/ghostty-git.git "$build_dir"
    cd "$build_dir" || exit

    log_info "Fixing the PKGBUILD (zig 0.16 package path, terminfo conflict with ncurses)..."
    sed -i 's|"$srcdir/zig-global-cache/p"|"$srcdir/$_pkgbase/zig-pkg"|' PKGBUILD
    sed -i 's|build/usr/share/terminfo/\*|build/usr/share/terminfo/x|' PKGBUILD

    log_info "Building Ghostty, this takes several minutes (output in /tmp/setup.log)..."
    makepkg -s --noconfirm

    # Installs the terminal and its dependencies, not the Nautilus extension
    log_info "Installing ghostty-git, ghostty-shell-integration-git and ghostty-terminfo-git..."
    local pkgs
    mapfile -t pkgs < <(makepkg --packagelist | grep -E '/ghostty-(shell-integration-|terminfo-)?git-[0-9]')
    sudo pacman -U --noconfirm "${pkgs[@]}"

    log_info "Removing the build directory..."
    cd "$HOME" || exit
    rm -rf "$build_dir"

    log_success "Ghostty built and installed."
}

# Builds rofi 2 from the Arch Linux PKGBUILD on ARM, whose repositories stop
# at rofi 1.7.5. That version only supports X11: Hyprland shows it through
# XWayland, which squashes and blurs it on a scaled screen.
_build_rofi() {
    local installed
    installed=$(pacman -Q rofi 2>/dev/null | cut -d ' ' -f 2)
    if [ -n "$installed" ] && [ "$(vercmp "$installed" 2)" -ge 0 ]; then
        log_warn "rofi $installed is already installed."
        return
    fi

    log_info "ARM repositories only have rofi 1.7.5 (X11 only), building rofi 2 from the Arch Linux PKGBUILD..."

    log_info "Installing pandoc-bin (provides pandoc, needed to build rofi)..."
    install_aur_pkg "pandoc-bin"

    local build_dir="$HOME/.cache/rofi-build"
    rm -rf "$build_dir"

    log_info "Downloading the rofi PKGBUILD..."
    git clone https://gitlab.archlinux.org/archlinux/packaging/packages/rofi.git "$build_dir"
    cd "$build_dir" || exit

    # The PKGBUILD only lists x86_64, but rofi builds on ARM as well
    log_info "Building rofi, running its tests and installing it (output in /tmp/setup.log)..."
    makepkg -si --noconfirm --ignorearch

    log_info "Removing the build directory..."
    cd "$HOME" || exit
    rm -rf "$build_dir"

    log_success "rofi $(pacman -Q rofi | cut -d ' ' -f 2) built and installed."
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

    log_info "Installing rofi (launcher and menus)..."
    if is_arm; then
        _build_rofi
    else
        install_pkg "rofi"
    fi

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
