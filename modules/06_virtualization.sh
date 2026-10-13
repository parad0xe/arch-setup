#!/bin/bash

# Installs QEMU/KVM with libvirt and the virt-manager GUI.
_install_qemu() {
    local pkgs=(
        "qemu-desktop"
        "libvirt"
        "virt-manager"
        "dnsmasq"
        "edk2-ovmf"
    )

    for pkg in "${pkgs[@]}"; do
        install_pkg "$pkg"
    done
}

# Enables libvirt, grants the user access to system VMs
# and starts the default NAT network.
_setup_libvirt() {
    log_info "Enabling libvirt service..."
    sudo systemctl enable --now libvirtd.service

    log_info "Adding $USER to the libvirt group..."
    sudo usermod -aG libvirt "$USER"

    log_info "Enabling default NAT network..."
    sudo virsh net-autostart default
    if ! sudo virsh net-info default | grep -q "Active:.*yes"; then
        sudo virsh net-start default
    fi
}

# Entry point for the virtualization module.
setup() {
    run_task "Installing QEMU/KVM..." _install_qemu
    run_task "Configuring libvirt..." _setup_libvirt
}
