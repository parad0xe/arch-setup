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

# Installs the tools used by .config/hypr/conf/vm.lua inside a VM.
_install_guest_tools() {
    # SPICE agent for clipboard sharing with the host
    install_pkg "spice-vdagent"
}

# Mounts the virtiofs share holding the dotfiles at boot, so the links
# created by the config module survive a reboot.
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

# Entry point for the virtualization module.
setup() {
    if systemd-detect-virt --vm --quiet; then
        run_task "Installing VM Guest Tools..." _install_guest_tools
        run_task "Persisting Dotfiles Share..." _persist_dotfiles_share
        return 0
    fi

    run_task "Installing QEMU/KVM..." _install_qemu
    run_task "Configuring libvirt..." _setup_libvirt
    run_task "Configuring firewall for VMs..." _setup_firewall
}
