#!/usr/bin/env bats
# lib/platform.sh: architecture, packages and services through the fake
# tools, boot loader detection, kernel command line and mkinitcpio modules
# on moved system files.

load test_helper

setup() {
    untraced repo_setup
}

# ---------- architecture ----------

@test "machine_arch, is_x86_64, is_arm on x86_64" {
    assert_equal "$(machine_arch)" "x86_64"
    is_x86_64
    ! is_arm
}

@test "machine_arch, is_x86_64, is_arm on aarch64" {
    export FAKE_ARCH=aarch64
    assert_equal "$(machine_arch)" "aarch64"
    is_arm
    ! is_x86_64
}

@test "neither on another architecture" {
    export FAKE_ARCH=armv7l
    ! is_arm
    ! is_x86_64
}

@test "in_vm asks systemd-detect-virt" {
    ! in_vm
    assert_fake_called "systemd-detect-virt --vm --quiet"
    FAKE_SYSTEMD_DETECT_VIRT_STATUS=0 in_vm
}

# ---------- packages and services ----------

@test "pkg_installed queries pacman" {
    pkg_installed fzf
    assert_fake_called "pacman -Qq fzf"
    export FAKE_PACMAN_MISSING="fzf chafa"
    ! pkg_installed fzf
    ! pkg_installed chafa
    pkg_installed git
}

@test "install_pkg installs with pacman through sudo, --needed and --noconfirm" {
    run install_pkg foo bar
    assert_equal "$status" 0
    assert_equal "$output" "[i] Installing: foo bar"
    assert_fake_called "sudo pacman -S --needed --noconfirm foo bar"
    assert_fake_called "pacman -S --needed --noconfirm foo bar"
}

@test "install_pkg fails when pacman fails" {
    export FAKE_PACMAN_STATUS=1
    run -1 install_pkg foo
}

@test "install_aur_pkg installs with yay, without sudo" {
    run install_aur_pkg brave-bin
    assert_equal "$output" "[i] Installing from the AUR: brave-bin"
    assert_fake_called "yay -S --needed --noconfirm brave-bin"
    assert_fake_not_called "sudo"
}

@test "enable_service enables a unit, its options before it" {
    run enable_service bluetooth.service
    assert_equal "$output" "[i] Enabling bluetooth.service..."
    assert_fake_called "sudo systemctl enable bluetooth.service"
    run enable_service pcscd.service --now
    assert_fake_called "sudo systemctl enable --now pcscd.service"
}

# ---------- boot loader ----------

@test "boot_loader: grub with its default file and grub-mkconfig" {
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' > "$GRUB_DEFAULT_FILE"
    assert_equal "$(boot_loader)" "grub"
}

@test "boot_loader: systemd-boot with its entries folder" {
    mkdir -p "$LOADER_ENTRIES_DIR"
    assert_equal "$(boot_loader)" "systemd-boot"
}

@test "boot_loader: grub wins when both are present, nothing when neither is" {
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' > "$GRUB_DEFAULT_FILE"
    mkdir -p "$LOADER_ENTRIES_DIR"
    assert_equal "$(boot_loader)" "grub"
    rm "$GRUB_DEFAULT_FILE"
    rmdir "$LOADER_ENTRIES_DIR"
    assert_equal "$(boot_loader)" ""
}

@test "boot_loader: grub without grub-mkconfig is not grub" {
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' > "$GRUB_DEFAULT_FILE"
    rm "$FAKE_BIN/grub-mkconfig"
    PATH="$FAKE_BIN:/nonexistent" run boot_loader
    assert_equal "$output" ""
}

@test "kernel_cmdline_add (GRUB): adds the parameter once and regenerates the menu" {
    printf 'GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"\n' > "$GRUB_DEFAULT_FILE"
    run kernel_cmdline_add nvidia_drm.modeset=1
    assert_equal "$status" 0
    assert_output_contains "[i] Adding nvidia_drm.modeset=1 to the GRUB command line..."
    assert_output_contains "[i] Regenerating the GRUB menu..."
    assert_file_contains "$GRUB_DEFAULT_FILE" 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"'
    assert_file_contains "$GRUB_DEFAULT_FILE" 'GRUB_TIMEOUT=5'
    assert_fake_called "sudo grub-mkconfig -o $GRUB_CFG_FILE"

    : > "$FAKE_LOG"
    run kernel_cmdline_add nvidia_drm.modeset=1
    assert_equal "$output" "[i] GRUB already has nvidia_drm.modeset=1."
    assert_equal "$(grep -c nvidia_drm "$GRUB_DEFAULT_FILE")" 1
    assert_fake_not_called "grub-mkconfig"
}

@test "kernel_cmdline_add (GRUB): appends the command line when the file has none" {
    echo 'GRUB_TIMEOUT=5' > "$GRUB_DEFAULT_FILE"
    kernel_cmdline_add nvidia_drm.modeset=1 > /dev/null
    assert_file_contains "$GRUB_DEFAULT_FILE" 'GRUB_CMDLINE_LINUX_DEFAULT="nvidia_drm.modeset=1"'
    assert_fake_called "grub-mkconfig -o $GRUB_CFG_FILE"
}

@test "kernel_cmdline_add (GRUB): warns when the command line is not double-quoted" {
    echo "GRUB_CMDLINE_LINUX_DEFAULT='quiet'" > "$GRUB_DEFAULT_FILE"
    run kernel_cmdline_add nvidia_drm.modeset=1
    assert_equal "$status" 0
    assert_output_contains "[!] GRUB_CMDLINE_LINUX_DEFAULT is not double-quoted in $GRUB_DEFAULT_FILE: add nvidia_drm.modeset=1 to it yourself."
    assert_fake_not_called "grub-mkconfig"
    assert_file_contains "$GRUB_DEFAULT_FILE" "GRUB_CMDLINE_LINUX_DEFAULT='quiet'"
}

@test "kernel_cmdline_add (systemd-boot): adds the parameter to every entry, idempotent" {
    mkdir -p "$LOADER_ENTRIES_DIR"
    printf 'title Arch\nlinux /vmlinuz-linux\noptions root=UUID=1 rw quiet\n' > "$LOADER_ENTRIES_DIR/arch.conf"
    printf 'title Fallback\noptions root=UUID=1 rw\n' > "$LOADER_ENTRIES_DIR/fallback.conf"
    printf 'options root=UUID=1 rw nvidia_drm.modeset=1 quiet\n' > "$LOADER_ENTRIES_DIR/done.conf"
    echo "not an entry" > "$LOADER_ENTRIES_DIR/notes.txt"

    run kernel_cmdline_add nvidia_drm.modeset=1
    assert_equal "$status" 0
    assert_output_contains "[i] Adding nvidia_drm.modeset=1 to the boot entry arch.conf..."
    assert_output_contains "[i] Adding nvidia_drm.modeset=1 to the boot entry fallback.conf..."
    assert_output_lacks "done.conf"
    assert_file_contains "$LOADER_ENTRIES_DIR/arch.conf" "options root=UUID=1 rw quiet nvidia_drm.modeset=1"
    assert_file_contains "$LOADER_ENTRIES_DIR/arch.conf" "linux /vmlinuz-linux"
    assert_file_contains "$LOADER_ENTRIES_DIR/fallback.conf" "options root=UUID=1 rw nvidia_drm.modeset=1"
    assert_equal "$(cat "$LOADER_ENTRIES_DIR/done.conf")" "options root=UUID=1 rw nvidia_drm.modeset=1 quiet"
    assert_equal "$(cat "$LOADER_ENTRIES_DIR/notes.txt")" "not an entry"
    assert_fake_not_called "grub-mkconfig"

    run kernel_cmdline_add nvidia_drm.modeset=1
    assert_equal "$output" "[i] The boot entries already have nvidia_drm.modeset=1."
    assert_equal "$(grep -c nvidia_drm "$LOADER_ENTRIES_DIR/arch.conf")" 1
}

@test "kernel_cmdline_add: only warns with an unknown boot loader" {
    run kernel_cmdline_add nvidia_drm.modeset=1
    assert_equal "$status" 0
    assert_equal "$output" "[!] Unknown boot loader: add nvidia_drm.modeset=1 to the kernel command line yourself."
    assert_fake_not_called "sudo"
}

# ---------- mkinitcpio ----------

@test "mkinitcpio_add_modules: adds the missing modules, keeps the present ones" {
    printf 'HOOKS=(base udev)\nMODULES=(btrfs nvidia)\n' > "$MKINITCPIO_CONF"
    run mkinitcpio_add_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm
    assert_equal "$status" 0
    assert_equal "$output" "[i] Loading nvidia_modeset nvidia_uvm nvidia_drm early (mkinitcpio)..."
    assert_file_contains "$MKINITCPIO_CONF" "MODULES=(btrfs nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
    assert_file_contains "$MKINITCPIO_CONF" "HOOKS=(base udev)"
    assert_equal "$(grep -c '^MODULES=' "$MKINITCPIO_CONF")" 1
}

@test "mkinitcpio_add_modules: leaves the file alone when every module is there" {
    echo 'MODULES=(nvidia nvidia_modeset)' > "$MKINITCPIO_CONF"
    run -0 mkinitcpio_add_modules nvidia_modeset nvidia
    assert_equal "$output" "[i] mkinitcpio already loads nvidia_modeset nvidia."
    assert_equal "$(cat "$MKINITCPIO_CONF")" "MODULES=(nvidia nvidia_modeset)"
    assert_fake_not_called "sudo"
}

@test "mkinitcpio_missing_modules: the modules not loaded yet, in order" {
    echo 'MODULES=(btrfs nvidia)' > "$MKINITCPIO_CONF"
    assert_equal "$(mkinitcpio_missing_modules nvidia nvidia_modeset nvidia_drm | tr '\n' ' ')" "nvidia_modeset nvidia_drm "
    assert_equal "$(mkinitcpio_missing_modules nvidia btrfs)" ""
    rm "$MKINITCPIO_CONF"
    assert_equal "$(mkinitcpio_missing_modules nvidia)" "nvidia"
}

@test "mkinitcpio_add_modules: fills an empty MODULES line" {
    echo 'MODULES=()' > "$MKINITCPIO_CONF"
    mkinitcpio_add_modules nvidia > /dev/null
    assert_equal "$(cat "$MKINITCPIO_CONF")" "MODULES=(nvidia)"
}

@test "mkinitcpio_add_modules: appends a MODULES line when there is none, ignoring commented ones" {
    printf '#MODULES=(old)\nHOOKS=(base)\n' > "$MKINITCPIO_CONF"
    mkinitcpio_add_modules nvidia nvidia_drm > /dev/null
    assert_equal "$(tail -n 1 "$MKINITCPIO_CONF")" "MODULES=(nvidia nvidia_drm)"
    assert_file_contains "$MKINITCPIO_CONF" "#MODULES=(old)"
}

@test "mkinitcpio_add_modules: a module whose name contains another is not a match" {
    echo 'MODULES=(nvidia_drm)' > "$MKINITCPIO_CONF"
    mkinitcpio_add_modules nvidia > /dev/null
    assert_equal "$(cat "$MKINITCPIO_CONF")" "MODULES=(nvidia_drm nvidia)"
}

# ---------- system files ----------

@test "ensure_line: adds a missing line once, keeps a present one" {
    local file="$SANDBOX/etc/fstab"
    printf 'UUID=1 / ext4 defaults 0 1\n' > "$file"
    run ensure_line "$file" "//nas/data /mnt/nas cifs credentials=/etc/samba/nas.cred,nofail 0 0"
    [ "$status" -eq 0 ]
    assert_output_contains "Adding to $file"
    run ensure_line "$file" "//nas/data /mnt/nas cifs credentials=/etc/samba/nas.cred,nofail 0 0"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    assert_equal "$(grep -c "/mnt/nas" "$file")" 1
    assert_equal "$(head -n 1 "$file")" "UUID=1 / ext4 defaults 0 1"
}

@test "ensure_line: replaces the line matching the key" {
    local file="$SANDBOX/etc/fstab"
    printf 'UUID=1 / ext4 defaults 0 1\n//nas/data /mnt/nas cifs defaults 0 0\n' > "$file"
    run ensure_line "$file" "//nas/data /mnt/nas cifs credentials=/etc/samba/nas.cred,nofail 0 0" '[[:space:]]/mnt/nas[[:space:]]'
    [ "$status" -eq 0 ]
    assert_output_contains "Replacing the line matching"
    assert_equal "$(grep -c "/mnt/nas" "$file")" 1
    assert_file_contains "$file" "credentials=/etc/samba/nas.cred"
    assert_file_lacks "$file" "cifs defaults 0 0"
}

