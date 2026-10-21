#!/bin/bash

module "Dual boot with GRUB"

# Returns success when GRUB is installed, outside a VM and not on ARM.
_can_dual_boot() {
    [ -f /etc/default/grub ] && ! is_arm && ! in_vm
}

# Returns success when GRUB can dual boot and an NTFS partition exists.
_can_dual_boot_windows() {
    _can_dual_boot && lsblk -nro FSTYPE | grep -qx ntfs
}

# Sets an option of /etc/default/grub, uncommented or appended.
#
# Args:
#   name: The option (e.g. GRUB_DEFAULT).
#   value: Its value.
_set_grub_option() {
    local grub="/etc/default/grub"
    if grep -q "^#*[[:space:]]*$1=" "$grub"; then
        sudo sed -i "s|^#*[[:space:]]*$1=.*|$1=$2|" "$grub"
    else
        echo "$1=$2" | sudo tee -a "$grub" > /dev/null
    fi
}

# Regenerates the GRUB menu.
_update_grub() {
    log_info "Regenerating GRUB config..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
}

# Installs os-prober and ntfs-3g (Windows partitions), enables os-prober in
# GRUB and regenerates its menu.
_setup_dualboot() {
    install_pkg "os-prober"
    install_pkg "ntfs-3g"

    log_info "Enabling os-prober in GRUB..."
    _set_grub_option GRUB_DISABLE_OS_PROBER false

    log_info "Looking for other systems..."
    local found device name
    found=$(sudo os-prober)
    if [ -z "$found" ]; then
        log_warn "No other system found (Windows: mount its EFI partition, then run ./setup.sh -b dualboot again)."
    else
        while IFS=: read -r device name _; do
            log_success "Found $name on ${device%%@*}"
        done <<< "$found"
    fi

    _update_grub
}

# GRUB selects the entry booted last time. Skipped when /boot/grub is on
# Btrfs, LVM, RAID or LUKS, where GRUB cannot save it.
_setup_grub_savedefault() {
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

# Asks whether the hardware clock is kept in local time, like Windows, or in
# UTC, then shows how to set Windows to UTC.
_setup_dualboot_clock() {
    local default="no"
    if [ "$(timedatectl show -p LocalRTC --value)" = "yes" ]; then
        default="yes"
    fi

    if confirm "Keep the hardware clock in local time, as Windows does?" "$default"; then
        log_info "Keeping the hardware clock in local time..."
        sudo timedatectl set-local-rtc 1
        return 0
    fi

    log_info "Keeping the hardware clock in UTC..."
    sudo timedatectl set-local-rtc 0
    log_warn "Set Windows to UTC too, in an administrator command prompt:
      reg add \"HKLM\\System\\CurrentControlSet\\Control\\TimeZoneInformation\" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f"
}

block dualboot             _setup_dualboot         "os-prober: other systems in the GRUB menu" --if _can_dual_boot
block dualboot.savedefault _setup_grub_savedefault "GRUB selects the entry booted last time" --if _can_dual_boot \
    --after dualboot
block dualboot.clock       _setup_dualboot_clock   "Hardware clock in local time or UTC, for Windows" --interactive \
    --if _can_dual_boot_windows \
    --after timezone
