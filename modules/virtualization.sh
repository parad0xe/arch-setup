#!/bin/bash

module "Virtual machines"

# Returns success when this machine can host VMs: not inside a VM, and not
# on ARM (no UEFI firmware package for ARM VMs).
_can_host_vms() {
    ! is_arm && ! in_vm
}

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

# Installs QEMU/KVM with libvirt and virt-manager, enables libvirt with its
# default NAT network, and lets VM traffic through UFW when it is active.
_setup_qemu() {
    _install_qemu
    _setup_libvirt
    _setup_firewall
}

# Installs the tools used by .config/hypr/conf/vm.lua inside a VM.
_install_guest_tools() {
    # SPICE agent for clipboard sharing with the host
    install_pkg "spice-vdagent"
}

# Mounts the virtiofs share holding the dotfiles at boot, so the config links
# survive a reboot.
_persist_dotfiles_share() {
    local fstype source target
    read -r fstype source target < <(findmnt -n -o FSTYPE,SOURCE,TARGET --target "$SETUP_DIR")

    if [ "$fstype" != "virtiofs" ]; then
        log_info "Dotfiles are not on a virtiofs share, skipping fstab entry."
        return 0
    fi

    local entry="$source ${target// /\\040} virtiofs defaults,nofail 0 0"
    if grep -qxF "$entry" /etc/fstab; then
        log_warn "fstab already mounts the '$source' share on $target."
        return 0
    fi

    log_info "Mounting the '$source' share on $target at boot..."
    sudo sed -i "\#^$source[[:space:]].*virtiofs#d" /etc/fstab
    echo "$entry" | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
}

# Installs the SPICE agent (clipboard shared with the host) and mounts the
# virtiofs share holding the dotfiles at boot.
_setup_vm_guest() {
    _install_guest_tools
    _persist_dotfiles_share
}

block qemu     _setup_qemu     "QEMU/KVM, libvirt and virt-manager" --if _can_host_vms
block vm-guest _setup_vm_guest "VM guest tools: SPICE agent, dotfiles share at boot" --if in_vm
