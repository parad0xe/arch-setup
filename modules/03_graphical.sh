#!/bin/bash

# Installs the Wayland window manager stack and related dependencies.
_install_wayland_stack() {
    local pkgs=(
        "hyprland"
        "waybar"
        "sddm"
        "wofi"
        "mako"
        "ttf-jetbrains-mono-nerd"
        "polkit-kde-agent"
        "qt5-wayland"
        "qt6-wayland"
        "qt5-graphicaleffects"
        "qt5-svg"
        "qt5-quickcontrols2"
		"socat"
    )

    log_info "Installing Wayland stack..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Installs the hypr stack.
_install_hypr_stack() {
    log_info "Installing hyprlock..."
    install_pkg "hyprlock"

    log_info "Installing hyprshutdown (used to log out)..."
    install_pkg "hyprshutdown"

    log_info "Installing hyprmon..."
	install_aur_pkg "hyprmon-bin"
}

# Installs the Bibata cursor theme used by the Hyprland config.
_install_cursor_theme() {
    log_info "Installing Bibata cursor theme..."
    install_aur_pkg "bibata-cursor-theme"
}

# Installs the Papirus icon theme and applies it to GTK apps. Rofi picks it
# from .config/rofi/config.rasi.
_setup_icon_theme() {
    log_info "Installing Papirus icon theme..."
    install_pkg "papirus-icon-theme"
    install_pkg "gsettings-desktop-schemas"

    log_info "Applying Papirus-Dark to GTK apps..."
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
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

# Enables the SDDM display manager service to start on boot.
_enable_sddm() {
    log_info "Enabling SDDM systemd service..."
    sudo systemctl enable -f sddm.service
}

# Entry point for the graphical module.
setup() {
	run_task "Installing Wayland Stack..." _install_wayland_stack
    run_task "Installing Hypr Stack..." _install_hypr_stack
    run_task "Installing Cursor Theme..." _install_cursor_theme
    run_task "Installing Icon Theme..." _setup_icon_theme
    run_task "Installing SDDM Theme..." _setup_sddm_theme
    run_task "Configuring SDDM Visuals..." _customize_sddm
    run_task "Enabling SDDM Service..." _enable_sddm
}
