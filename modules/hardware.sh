#!/bin/bash

# Installs NetworkManager (nmcli) and enables the service.
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

# Installs the Bluetooth stack (bluez, bluetoothctl) and enables the service.
_setup_bluetooth() {
    local pkgs=(
        "bluez"
        "bluez-utils"
    )

    log_info "Installing Bluetooth packages..."
    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done

    log_info "Enabling bluetooth service..."
    sudo systemctl enable bluetooth.service
}

# Returns success when a PCI device from NVIDIA (vendor id 0x10de) is present.
_has_nvidia_gpu() {
    grep -qsx "0x10de" /sys/bus/pci/devices/*/vendor
}

# Installs the NVIDIA drivers (nvidia-open-dkms, nvidia-prime for prime-run),
# loads them early (mkinitcpio) and enables DRM modeset in GRUB.
_setup_nvidia() {
    log_info "Cleaning up conflicting NVIDIA packages..."
    local conflict_pkgs=("nvidia" "nvidia-open")
    for pkg in "${conflict_pkgs[@]}"; do
        sudo pacman -R --noconfirm "$pkg" 2>/dev/null || true
    done

    local pkgs=(
        "linux-headers"
        "nvidia-open-dkms"
        "nvidia-utils"
        "lib32-nvidia-utils"
        "egl-wayland"
        "nvidia-settings"
        "nvidia-prime"
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

    _setup_grub_nvidia
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

# Installs the smartcard stack used by security keys such as a YubiKey
# (pcsclite, ccid) and enables pcscd.
_setup_securitykey() {
    log_info "Installing Smartcard packages..."
    install_pkg "pcsclite"
    install_pkg "ccid"

    log_info "Enabling pcscd service..."
    sudo systemctl enable --now pcscd.service
}

block network     _setup_network     "NetworkManager"
block audio       _setup_audio       "PipeWire audio stack"
block bluetooth   _setup_bluetooth   "Bluetooth stack (bluez)"
block nvidia      _setup_nvidia      "NVIDIA drivers, early loading, GRUB DRM modeset" --if _has_nvidia_gpu
block securitykey _setup_securitykey "Smartcard stack for security keys (pcscd)"
