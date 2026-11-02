#!/bin/bash
# Hooks of modules/desktop.toml, run by lib/hook.sh.

# Restarts Waybar when it runs, so that it loads the deployed config and
# theme, or starts it when asked to; nothing outside a Wayland session (TTY,
# SSH). setsid detaches it from the setup and its terminal.
#
# Inputs: INPUT_START_WAYBAR (1 to start it when it does not run).
reload_waybar() {
    if [ -z "${WAYLAND_DISPLAY-}" ]; then
        return 0
    fi

    if pgrep -x waybar > /dev/null; then
        log_info "Restarting Waybar..."
        killall waybar || true
        setsid -f waybar > /dev/null 2>&1
    elif [ "${INPUT_START_WAYBAR:-0}" = 1 ]; then
        log_info "Starting Waybar..."
        setsid -f waybar > /dev/null 2>&1
    fi
}

# Builds rofi 2 from the Arch Linux PKGBUILD on ARM, where the unit runs
# this hook: the repositories stop at rofi 1.7.5, which only supports X11
# (Hyprland shows it through XWayland, which squashes and blurs it on a
# scaled screen). x86_64 installs the rofi package.
build_rofi() {
    local installed
    installed=$(pacman -Q rofi 2> /dev/null | cut -d ' ' -f 2)
    if [ -n "$installed" ] && [ "$(vercmp "$installed" 2)" -ge 0 ]; then
        log_warn "rofi $installed is already installed."
        return 0
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
    log_info "Building rofi, running its tests and installing it..."
    makepkg -si --noconfirm --ignorearch

    log_info "Removing the build directory..."
    cd "$HOME" || exit
    rm -rf "$build_dir"

    log_success "rofi $(pacman -Q rofi | cut -d ' ' -f 2) built and installed."
}

# Builds wlctl, the Wi-Fi manager, from the AUR (wlctl-git) with the
# passphrase hidden while it is typed (Ctrl+H shows it): wlctl shows it by
# default, and no setting changes that. Built with cargo, on x86_64 and ARM.
# It replaces wlctl-bin, installed by hand.
build_wlctl() {
    if pacman -Q wlctl-git &> /dev/null; then
        log_warn "wlctl is already built."
        return 0
    fi

    local build_dir="$HOME/.cache/wlctl-git-build"
    rm -rf "$build_dir"

    log_info "Downloading the wlctl-git PKGBUILD..."
    git clone https://aur.archlinux.org/wlctl-git.git "$build_dir"
    cd "$build_dir" || exit

    # -o downloads and prepares the sources without building them, so that
    # they can be changed before the build
    log_info "Downloading the wlctl sources and their crates..."
    makepkg -o -s --noconfirm

    log_info "Hiding the passphrase while it is typed..."
    local psk="src/wlctl/src/mode/station/auth/psk.rs"
    sed -i 's/show_password: true,/show_password: false,/' "$psk"
    if ! grep -q 'show_password: false,' "$psk"; then
        log_error "wlctl changed: the passphrase cannot be hidden ($psk)."
        return 1
    fi

    # -e builds the changed sources instead of extracting them again
    log_info "Building wlctl, this takes a few minutes..."
    makepkg -e --nocheck --noconfirm

    # yes answers the removal of wlctl-bin, which conflicts with wlctl-git
    log_info "Installing wlctl-git..."
    local pkgs
    mapfile -t pkgs < <(makepkg --packagelist)
    yes | sudo pacman -U "${pkgs[@]}"

    log_info "Removing the build directory..."
    cd "$HOME" || exit
    rm -rf "$build_dir"

    log_success "wlctl built and installed."
}

# Applies the Tokyo Night theme installed by the unit to SDDM, with its
# colors. Its background is background.jpg, written by the wallpaper
# selector ("Apply to" login); until one is applied, SDDM shows the
# background color.
setup_sddm_theme() {
    log_info "Applying the theme to the SDDM configuration..."
    sudo mkdir -p /etc/sddm.conf.d
    printf '[Theme]\nCurrent=tokyo-night-sddm\n' | sudo tee /etc/sddm.conf.d/theme.conf > /dev/null

    local conf="/usr/share/sddm/themes/tokyo-night-sddm/theme.conf"
    log_info "Customizing the SDDM theme colors..."
    sudo sed -i 's|^Background=.*|Background="background.jpg"|' "$conf"
    sudo sed -i 's|^MainColor=.*|MainColor="#cdd6f4"|' "$conf"
    sudo sed -i 's|^AccentColor=.*|AccentColor="#89b4fa"|' "$conf"
    sudo sed -i 's|^BackgroundColor=.*|BackgroundColor="#1e1e2e"|' "$conf"

    local h_align="BackgroundImageHAlignment"
    local v_align="BackgroundImageVAlignment"
    sudo sed -i "s|^$h_align=.*|$h_align=\"center\"|" "$conf"
    sudo sed -i "s|^$v_align=.*|$v_align=\"center\"|" "$conf"
}

# Applies the Papirus-Dark icon theme to GTK apps; nothing without a session
# bus (TTY, SSH).
apply_icon_theme() {
    log_info "Applying Papirus-Dark to GTK apps..."
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" \
        || log_warn "Papirus-Dark could not be applied now (no session bus): run the icons unit again from the desktop."
}

# Restarts the desktop portal so that it picks up the Hyprland and GTK
# backends just installed; nothing without a user session (a TTY install).
restart_desktop_portal() {
    if [ -z "${XDG_RUNTIME_DIR-}" ]; then
        log_info "No user session: the portal starts with the next login."
        return 0
    fi
    log_info "Restarting the desktop portal..."
    systemctl --user restart xdg-desktop-portal \
        || log_warn "The desktop portal could not be restarted now: it starts with the next login."
}
