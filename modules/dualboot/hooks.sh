#!/bin/bash
# Hooks of modules/dualboot.toml, run by lib/hook.sh.

# Sets an option of /etc/default/grub, uncommented or appended.
#
# Args:
#   name: The option (e.g. GRUB_DEFAULT).
#   value: Its value.
_set_grub_option() {
    local grub="$GRUB_DEFAULT_FILE"
    if grep -q "^#*[[:space:]]*$1=" "$grub"; then
        sudo sed -i "s|^#*[[:space:]]*$1=.*|$1=$2|" "$grub"
    else
        echo "$1=$2" | sudo tee -a "$grub" > /dev/null
    fi
}

# Regenerates the GRUB menu.
_update_grub() {
    log_info "Regenerating the GRUB menu..."
    sudo grub-mkconfig -o "$GRUB_CFG_FILE"
}

# Enables os-prober in GRUB (os-prober and ntfs-3g are installed by the
# unit), looks for other systems and regenerates the menu.
setup_dualboot() {
    log_info "Enabling os-prober in GRUB..."
    _set_grub_option GRUB_DISABLE_OS_PROBER false

    log_info "Looking for other systems..."
    local found device name
    found=$(sudo os-prober)
    if [ -z "$found" ]; then
        log_warn "No other system found (Windows: mount its EFI partition, then run the dualboot unit again)."
    else
        while IFS=: read -r device name _; do
            log_success "Found $name on ${device%%@*}"
        done <<< "$found"
    fi

    _update_grub
}

# Makes GRUB select the entry booted last time. Skipped when /boot/grub is
# on Btrfs, LVM, RAID or LUKS, where GRUB cannot save it.
setup_grub_savedefault() {
    local source fstype
    read -r source fstype <<< "$(sudo findmnt -no SOURCE,FSTYPE --target /boot/grub || true)"
    if [ "$fstype" = "btrfs" ] || [[ "$source" == /dev/mapper/* || "$source" == /dev/md* ]]; then
        log_warn "GRUB cannot save the last entry on $source ($fstype), skipping."
        return 0
    fi

    log_info "Making GRUB select the entry booted last time..."
    _set_grub_option GRUB_DEFAULT saved
    _set_grub_option GRUB_SAVEDEFAULT true

    _update_grub
}

# Keeps the hardware clock in local time, like Windows, or in UTC, then
# shows how to set Windows to UTC.
#
# Inputs: INPUT_CLOCK (utc or localtime).
setup_dualboot_clock() {
    if [ "${INPUT_CLOCK:-utc}" = localtime ]; then
        log_info "Keeping the hardware clock in local time..."
        sudo timedatectl set-local-rtc 1
        return 0
    fi

    log_info "Keeping the hardware clock in UTC..."
    sudo timedatectl set-local-rtc 0
    log_warn "Set Windows to UTC too, in an administrator command prompt:
      reg add \"HKLM\\System\\CurrentControlSet\\Control\\TimeZoneInformation\" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f"
}
