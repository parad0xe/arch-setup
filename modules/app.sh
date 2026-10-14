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

# Installs the Ghostty terminal (built from the AUR on ARM) and links its
# config.
_install_ghostty() {
    log_info "Installing Ghostty terminal..."
    if is_arm; then
        _build_ghostty_git
    else
        install_pkg "ghostty"
    fi

    log_info "Linking Ghostty config..."
    link_config "$SETUP_DIR/.config/ghostty" "$HOME/.config/ghostty"
}

# Installs the Brave web browser.
_install_brave() {
    log_info "Installing Brave..."
    install_aur_pkg "brave-bin"
}

# Installs the Thunar file manager with archive support (thunar-archive-plugin,
# file-roller) and gvfs (trash, removable drives, network shares).
_install_thunar() {
    local pkgs=(
        "thunar"
        "thunar-archive-plugin"
        "file-roller"
        "gvfs"
    )

    log_info "Installing Thunar..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Installs the KeePass password manager.
_install_keepass() {
    log_info "Installing KeePass..."
    install_pkg "keepass"
}

# Installs the Krita painting program.
_install_krita() {
    log_info "Installing Krita..."
    install_pkg "krita"
}

# Installs JetBrains Toolbox, which installs and updates the JetBrains IDEs
# (x86_64 only).
_install_jetbrains_toolbox() {
    log_info "Installing JetBrains Toolbox..."
    install_aur_pkg "jetbrains-toolbox"
}

# Installs Discord (x86_64 only).
_install_discord() {
    log_info "Installing Discord..."
    install_pkg "discord"
}

# Installs Yubico Authenticator, which shows the OTP codes stored on a
# YubiKey (x86_64 only).
_install_yubico_authenticator() {
    log_info "Installing Yubico Authenticator..."
    install_aur_pkg "yubico-authenticator-bin"
}

# Its config uses the JetBrains Mono Nerd Font
block app.ghostty _install_ghostty "Ghostty terminal and its config" \
    --needs fonts

block app.brave    _install_brave    "Brave web browser"
block app.thunar   _install_thunar   "Thunar file manager with archive support"
block app.keepass  _install_keepass  "KeePass password manager"
block app.krita    _install_krita    "Krita painting program"

# Only published for x86_64
block app.jetbrains _install_jetbrains_toolbox    "JetBrains Toolbox" --unless is_arm
block app.discord   _install_discord              "Discord"           --unless is_arm

# It reads the YubiKey through the pcscd service
block app.yubico    _install_yubico_authenticator "Yubico Authenticator" --unless is_arm \
    --needs securitykey
