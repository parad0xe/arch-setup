#!/bin/bash

module "Hyprland desktop"

# Installs Hyprland with its bar (Waybar), notifications (mako), polkit
# agent and Qt Wayland support.
_install_desktop() {
    local pkgs=(
        "hyprland"
        "waybar"
        "mako"
        "polkit-kde-agent"
        "qt5-wayland"
        "qt6-wayland"
    )

    log_info "Installing Hyprland stack..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Installs the Hypr tools the config runs: hyprlock (lock screen),
# hyprshutdown (log out) and hyprmon (monitor layout, saved outside the
# dotfiles).
_install_hypr_tools() {
    log_info "Installing hyprlock..."
    install_pkg "hyprlock"

    log_info "Installing hyprshutdown (used to log out)..."
    install_pkg "hyprshutdown"

    log_info "Installing hyprmon..."
    install_aur_pkg "hyprmon-bin"
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

# Installs the tools the Hyprland and Waybar configs run: rofi (launcher and
# menus), wlogout (power menu), grim, slurp and satty (screenshots),
# wl-clipboard, playerctl (media keys), libnotify (notifications),
# brightnessctl, pavucontrol, socat (monitor hotplug script) and btop.
_install_desktop_tools() {
    local pkgs=(
        "wl-clipboard"
        "grim"
        "slurp"
        "satty"
        "playerctl"
        "libnotify"
        "brightnessctl"
        "pavucontrol"
        "socat"
        "btop"
    )

    log_info "Installing desktop tools..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Installing rofi (launcher and menus)..."
    if is_arm; then
        _build_rofi
    else
        install_pkg "rofi"
    fi

    log_info "Installing wlogout (power menu)..."
    install_aur_pkg "wlogout"
}

# Installs the tray applets started by the Hyprland config: nm-applet
# (network) and blueman (Bluetooth, also opened from Waybar).
_install_applets() {
    log_info "Installing network and Bluetooth applets..."
    install_pkg "network-manager-applet"
    install_pkg "blueman"
}

# Installs what the wallpaper scripts run: awww (images), mpvpaper (videos)
# and ffmpegthumbnailer (video thumbnails in the selector).
_install_wallpaper_engines() {
    log_info "Installing wallpaper engines..."
    install_pkg "awww"
    install_pkg "ffmpegthumbnailer"
    install_aur_pkg "mpvpaper"
}

# Installs and applies the Tokyo Night theme for SDDM.
_setup_sddm_theme() {
    log_info "Installing SDDM Tokyo Night theme..."
    install_aur_pkg "sddm-theme-tokyo-night-git"

    log_info "Applying theme to SDDM configuration..."
    sudo mkdir -p /etc/sddm.conf.d

    echo -e "[Theme]\nCurrent=tokyo-night-sddm" | \
        sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
}

# Customizes the SDDM theme colors. Its background is background.jpg, written
# by the wallpaper selector ("Apply to" login); until one is applied, SDDM
# shows the background color.
_customize_sddm() {
    local conf="/usr/share/sddm/themes/tokyo-night-sddm/theme.conf"

    log_info "Customizing SDDM theme visuals..."
    sudo sed -i 's|^Background=.*|Background="background.jpg"|' "$conf"
    sudo sed -i 's|^MainColor=.*|MainColor="#cdd6f4"|' "$conf"
    sudo sed -i 's|^AccentColor=.*|AccentColor="#89b4fa"|' "$conf"
    sudo sed -i 's|^BackgroundColor=.*|BackgroundColor="#1e1e2e"|' "$conf"

    local h_align="BackgroundImageHAlignment"
    local v_align="BackgroundImageVAlignment"
    sudo sed -i "s|^$h_align=.*|$h_align=\"center\"|" "$conf"
    sudo sed -i "s|^$v_align=.*|$v_align=\"center\"|" "$conf"
}

# Installs the SDDM login screen with the Qt modules of its Tokyo Night
# theme, applies the theme and its colors, and enables SDDM at boot.
_setup_sddm() {
    local pkgs=(
        "sddm"
        "qt5-graphicaleffects"
        "qt5-svg"
        "qt5-quickcontrols2"
    )

    log_info "Installing SDDM..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    _setup_sddm_theme
    _customize_sddm

    log_info "Enabling SDDM systemd service..."
    sudo systemctl enable -f sddm.service
}

# Installs the Bibata cursor theme set by the Hyprland config (the default
# cursor shows without it).
_install_cursor_theme() {
    log_info "Installing Bibata cursor theme..."
    install_aur_pkg "bibata-cursor-theme"
}

# Installs the Papirus icon theme and applies it to GTK apps. Rofi picks it
# from .config/rofi/config.rasi (it shows no icons without it).
_setup_icon_theme() {
    log_info "Installing Papirus icon theme..."
    install_pkg "papirus-icon-theme"
    install_pkg "gsettings-desktop-schemas"

    log_info "Applying Papirus-Dark to GTK apps..."
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
}

# Installs ddcutil, which the brightness menu uses to set the brightness of
# external monitors over DDC/CI when it is installed. The package loads
# i2c-dev at boot and grants the logged-in user access to the monitors' i2c
# buses.
_setup_ddcutil() {
    log_info "Installing ddcutil..."
    install_pkg "ddcutil"
}

# Installs the JetBrains Mono Nerd Font, used by Waybar, mako, rofi,
# hyprlock and Ghostty (its glyphs show as boxes without it).
_install_fonts() {
    log_info "Installing JetBrains Mono Nerd Font..."
    install_pkg "ttf-jetbrains-mono-nerd"
}

block desktop _install_desktop "Hyprland desktop: Hyprland, Waybar, mako, polkit agent"

block desktop.hypr-tools         _install_hypr_tools        "hyprlock (lock), hyprshutdown (log out), hyprmon (monitors)"
block desktop.tools              _install_desktop_tools     "rofi, wlogout, screenshots, clipboard, media keys, notifications"
block desktop.applets            _install_applets           "Network and Bluetooth tray applets (nm-applet, blueman)" \
    --needs network \
    --needs bluetooth
block desktop.wallpaper-engines  _install_wallpaper_engines "Wallpaper engines: awww (images), mpvpaper (videos)"
block desktop.sddm               _setup_sddm                "SDDM login screen with the Tokyo Night theme"
block desktop.cursor             _install_cursor_theme      "Bibata cursor theme"
block desktop.icons              _setup_icon_theme          "Papirus-Dark icon theme"
block desktop.ddcutil            _setup_ddcutil             "ddcutil: external monitors brightness in the brightness menu"

block fonts _install_fonts "JetBrains Mono Nerd Font"

# The Hyprland config runs commands from these blocks: keybindings (terminal,
# browser, file manager, lock, launcher, screenshots, volume), autostart
# (applets, wallpaper engines) and its scripts. Its launcher and wallpaper
# selector use the rofi themes.
config hypr .config/hypr .config/hypr "Hyprland: keybindings, autostart, scripts" --block desktop \
    --program Hyprland \
    --needs desktop.hypr-tools \
    --needs desktop.tools \
    --needs desktop.applets \
    --needs desktop.wallpaper-engines \
    --needs audio \
    --needs fonts \
    --needs app.ghostty \
    --needs app.brave \
    --needs app.nautilus \
    --needs-config rofi

# Its modules run the Hyprland scripts (wifi, brightness, laptop keyboard),
# pavucontrol, blueman, wlogout, and btop in Ghostty
config waybar .config/waybar .config/waybar "Waybar bar and its modules" --block desktop \
    --program waybar \
    --needs desktop.tools \
    --needs desktop.applets \
    --needs app.ghostty \
    --needs fonts \
    --needs-config hypr

config mako .config/mako .config/mako "mako notifications" --block desktop \
    --program mako \
    --needs fonts

config rofi .config/rofi .config/rofi "rofi launcher and menu themes" --block desktop.tools \
    --program rofi \
    --needs fonts

# Its lock and log out buttons run the Hyprland scripts
config wlogout .config/wlogout .config/wlogout "wlogout power menu" --block desktop.tools \
    --program wlogout \
    --needs fonts \
    --needs-config hypr
