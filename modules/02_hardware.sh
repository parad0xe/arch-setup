#!/bin/bash

# Installs and enables the NetworkManager service.
_setup_network() {
    log_info "Installing NetworkManager..."
    install_pkg "networkmanager"

    log_info "Enabling NetworkManager service..."
    sudo systemctl enable NetworkManager.service
}

# Installs the PipeWire audio stack and WirePlumber.
_setup_audio() {
    local pkgs=(
        "pipewire"
        "pipewire-alsa"
        "pipewire-pulse"
        "pipewire-jack"
        "wireplumber"
    )

    log_info "Installing PipeWire audio stack..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Installs Bluetooth utilities and enables the service.
_setup_bluetooth() {
    local pkgs=(
        "bluez"
        "bluez-utils"
        "blueman"
    )

    log_info "Installing Bluetooth packages..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Enabling bluetooth service..."
    sudo systemctl enable bluetooth.service
}

# Installs NVIDIA drivers and configures early module loading.
_setup_nvidia() {
    log_info "Cleaning up conflicting NVIDIA packages..."
	local conflict_pkgs=("nvidia" "nvidia-open")
  	for pkg in "${conflict_pkgs[@]}"; do
    	sudo pacman -R --noconfirm "$pkg" 2>/dev/null || true
  	done

    local pkgs=(
        "linux-headers"
        "nvidia-dkms"
        "nvidia-utils"
        "lib32-nvidia-utils"
        "egl-wayland"
        "nvidia-settings"
    )

    log_info "Installing NVIDIA drivers..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Configuring early module loading..."
    local mkinit="/etc/mkinitcpio.conf"
    local mods="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
    sudo sed -i "s/MODULES=()/MODULES=($mods)/" "$mkinit"
    sudo mkinitcpio -P
}

# Configures GRUB with NVIDIA DRM modeset for Wayland support.
_setup_grub_nvidia() {
    local grub="/etc/default/grub"
    local param="nvidia_drm.modeset=1"

    if ! grep -q "$param" "$grub"; then
        log_info "Adding $param to GRUB..."
        local pattern="\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\""
        sudo sed -i "s/$pattern/\1 $param\"/" "$grub"

        log_info "Regenerating GRUB config..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
        log_warn "GRUB is already configured for NVIDIA DRM."
    fi
}

_setup_securitykey() {
	log_info "Installing Smartcard packages..."
    install_pkg "pcsclite"
    install_pkg "ccid"

    log_info "Enabling pcscd service..."
    sudo systemctl enable --now pcscd.service
}

setup() {
	run_task "Installing Networking Tools..." _setup_network
    run_task "Installing Audio Stack..." _setup_audio
    run_task "Installing Bluetooth Tools..." _setup_bluetooth
    run_task "Installing NVIDIA Drivers..." _setup_nvidia
    run_task "Configuring GRUB for NVIDIA..." _setup_grub_nvidia
	run_task "Configuring Smartcard Services..." _setup_securitykey
}
