#!/bin/bash
# Hooks of modules/virtualization.toml, run by lib/hook.sh.

# Lets VMs reach libvirt's DHCP/DNS and the Internet when UFW is active.
_allow_vm_traffic() {
    if ! command -v ufw > /dev/null 2>&1 || ! sudo ufw status | grep -q "Status: active"; then
        log_info "UFW is not active, skipping the firewall rules."
        return 0
    fi

    log_info "Allowing VM traffic on virbr0 through UFW..."
    sudo ufw allow in on virbr0
    sudo ufw route allow in on virbr0
}

# Grants the user access to system VMs, starts the default NAT network and
# lets VM traffic through UFW when it is active. libvirtd is enabled by the
# unit.
setup_libvirt() {
    log_info "Adding $USER to the libvirt group..."
    sudo usermod -aG libvirt "$USER"

    log_info "Enabling the default NAT network..."
    sudo virsh net-autostart default
    if ! sudo virsh net-info default | grep -q "Active:.*yes"; then
        sudo virsh net-start default
    fi

    _allow_vm_traffic
}

# Mounts the virtiofs share holding the dotfiles at boot, so that the config
# links survive a reboot.
persist_dotfiles_share() {
    local fstype source target
    read -r fstype source target < <(findmnt -n -o FSTYPE,SOURCE,TARGET --target "$SETUP_DIR")

    if [ "$fstype" != "virtiofs" ]; then
        log_info "The dotfiles are not on a virtiofs share, skipping the fstab entry."
        return 0
    fi

    local entry="$source ${target// /\\040} virtiofs defaults,nofail 0 0"
    if grep -qxF "$entry" /etc/fstab; then
        log_warn "fstab already mounts the '$source' share on $target."
        return 0
    fi

    log_info "Mounting the '$source' share on $target at boot..."
    sudo sed -i "\#^${source}[[:space:]].*virtiofs#d" /etc/fstab
    echo "$entry" | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
}
