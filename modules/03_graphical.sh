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
    )

    log_info "Installing Wayland stack..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Installs the hyprlock screen locker.
_install_hyprlock() {
    log_info "Installing hyprlock..."
    install_pkg "hyprlock"
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

# Customizes the SDDM theme with a specific background and colors.
#
# Args:
#   img: Path to the background image.
_customize_sddm() {
    local img="$1"
    local theme_dir="/usr/share/sddm/themes/tokyo-night-sddm"
    local conf="$theme_dir/theme.conf"

    log_info "Customizing SDDM theme visuals..."
    sudo cp "$img" "$theme_dir/background.jpg"
    sudo chmod 644 "$theme_dir/background.jpg"

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
    run_task "Installing Hyprlock..." _install_hyprlock
    run_task "Installing SDDM Theme..." _setup_sddm_theme
    run_task "Configuring SDDM Visuals..." _customize_sddm "$CFG_LOCK_BG_IMG"
    run_task "Enabling SDDM Service..." _enable_sddm
}
