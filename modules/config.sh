#!/bin/bash

# Links the SSH config, whose machine-specific hosts and keys go in
# ~/.ssh/config.d/ (not versioned), then generates an SSH ed25519 or
# ed25519-sk (FIDO2 security key) key, asking for its email.
_setup_ssh() {
    local ssh_dir="$HOME/.ssh"
    mkdir -p -m 700 "$ssh_dir" "$ssh_dir/config.d"
    chmod 700 "$ssh_dir"
    link_config "$SETUP_DIR/.config/ssh/config" "$ssh_dir/config"

    local ssh_email=""
    while [ -z "$ssh_email" ]; do
        printf "\r\033[K\033[1;34m[i]\033[0m Enter the email for SSH: " > /dev/tty
        read -r ssh_email < /dev/tty
    done

    log_info "Setting up SSH key for $ssh_email..."

    local use_sk="n"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to use a Security Key for SSH? [y/N]: " > /dev/tty
    read -r use_sk < /dev/tty

    if [[ "$use_sk" =~ ^[Yy]$ ]]; then
        # ==========================================
        # FIDO2 / YUBIKEY LOGIC
        # ==========================================
        local key_path="$ssh_dir/id_ed25519_sk"

        if ls "$ssh_dir/id_ed25519_sk"* 1> /dev/null 2>&1; then
            log_warn "A FIDO2 SSH key already exists locally."
            return
        fi

        log_info "Please ensure your Security Key is plugged in."
        log_info "Attempting to download a resident key..."
        log_info "(Enter your FIDO2 PIN if prompted, then touch your Security Key when it blinks)"

        cd "$ssh_dir" || exit
        if ssh-keygen -K; then
            log_success "Resident key successfully retrieved from the Security Key."
        else
            log_warn "No resident key found on the Security Key. Generating a new key..."

            local passphrase
            getpass "Please enter your local SSH passphrase (or press Enter for none):" passphrase

            log_info "Please touch your Security Key when it blinks..."
            ssh-keygen -t ed25519-sk -O resident -O verify-required -C "$ssh_email" -f "$key_path" -N "$passphrase"

            unset passphrase
        fi
        cd - > /dev/null || exit

    else
        # ==========================================
        # STANDARD SSH LOGIC
        # ==========================================
        local key_path="$ssh_dir/id_ed25519"

        if [ -f "$key_path" ]; then
            log_warn "Standard SSH key already exists at $key_path."
            return
        fi

        log_info "Generating standard ed25519 SSH key..."
        local passphrase
        getpass "Please enter your SSH passphrase (or press Enter for none):" passphrase

        ssh-keygen -t ed25519 -C "$ssh_email" -f "$key_path" -N "$passphrase"

        unset passphrase
    fi
}

# Configures the global Git name and email, asked for, and main as the
# default branch.
_setup_git() {
    local git_user=""
    local git_email=""

    while [ -z "$git_user" ]; do
        printf "\r\033[K\033[1;34m[i]\033[0m Enter your Git username: " > /dev/tty
        read -r git_user < /dev/tty
    done

    while [ -z "$git_email" ]; do
        printf "\r\033[K\033[1;34m[i]\033[0m Enter your Git email: " > /dev/tty
        read -r git_email < /dev/tty
    done

    log_info "Configuring global Git settings..."
    git config --global user.name "$git_user"
    git config --global user.email "$git_email"
    git config --global init.defaultBranch main
}

# Asks for the system timezone (default: the current one) and enables NTP
# synchronization.
_setup_time() {
    local current
    current=$(timedatectl show -p Timezone --value)

    local tz=""
    while true; do
        printf "\r\033[K\033[1;34m[i]\033[0m Timezone [%s]: " "$current" > /dev/tty
        read -r tz < /dev/tty
        tz="${tz:-$current}"

        if timedatectl list-timezones | grep -Fxq "$tz"; then
            break
        fi
        log_warn "Unknown timezone: $tz"
    done

    log_info "Configuring system time for $tz..."
    sudo timedatectl set-timezone "$tz"
    sudo timedatectl set-ntp true
    sudo hwclock --systohc
}

block ssh      _setup_ssh  "SSH config and key (standard or FIDO2 security key)" --interactive
block git      _setup_git  "Git name, email and default branch" --interactive
block timezone _setup_time "System timezone and NTP synchronization" --interactive
