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

# Lets VMs reach libvirt's DHCP/DNS and the Internet when UFW is active.
_setup_firewall() {
    if ! command -v ufw > /dev/null 2>&1 || ! sudo ufw status | grep -q "Status: active"; then
        log_info "UFW is not active, skipping firewall rules."
        return 0
    fi

    log_info "Allowing VM traffic on virbr0 through UFW..."
    sudo ufw allow in on virbr0
    sudo ufw route allow in on virbr0
}

# Entry point for the virtualization module.
setup() {
    run_task "Installing QEMU/KVM..." _install_qemu
    run_task "Configuring libvirt..." _setup_libvirt
    run_task "Configuring firewall for VMs..." _setup_firewall
}
