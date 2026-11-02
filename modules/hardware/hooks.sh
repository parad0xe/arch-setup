#!/bin/bash
# Hooks of modules/hardware.toml, run by lib/hook.sh.

# Restarts WirePlumber when it runs, so that it applies its deployed config.
restart_wireplumber() {
    log_info "Restarting WirePlumber..."
    systemctl --user try-restart wireplumber.service \
        || log_warn "WirePlumber could not be restarted: log in again to apply its config."
}

# Loads the NVIDIA modules early (mkinitcpio) and enables DRM modeset on the
# kernel command line (GRUB or systemd-boot). The drivers are installed by
# the unit.
setup_nvidia() {
    local missing
    missing=$(mkinitcpio_missing_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm)
    if [ -n "$missing" ]; then
        mkinitcpio_add_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm
        log_info "Rebuilding the initramfs..."
        sudo mkinitcpio -P
    fi

    kernel_cmdline_add "nvidia_drm.modeset=1"
}

# Makes the boot load the microcode installed by the unit: GRUB regenerates
# its menu; with another boot loader, mkinitcpio's microcode hook must be
# enabled.
setup_microcode() {
    local vendor
    vendor=$(cpu_vendor)
    if [ -z "$vendor" ]; then
        log_warn "Unknown CPU vendor: no microcode to load."
        return 0
    fi

    if [ "$(boot_loader)" = grub ]; then
        if ! sudo grep -qs "$vendor-ucode" "$GRUB_CFG_FILE"; then
            log_info "Regenerating the GRUB menu, which loads the microcode..."
            sudo grub-mkconfig -o "$GRUB_CFG_FILE"
        fi
    elif ! grep -Eq '^HOOKS=.*microcode' "$MKINITCPIO_CONF"; then
        log_warn "Add microcode to the HOOKS of $MKINITCPIO_CONF (then run mkinitcpio -P), or an 'initrd /$vendor-ucode.img' line to the boot entries."
    fi
}
