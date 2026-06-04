#!/bin/bash

# Generates an SSH ed25519 or ed25519-sk (FIDO2) key interactively.
_setup_ssh_key() {
    local do_setup="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to configure SSH? [Y/n]: " > /dev/tty
    read -r do_setup < /dev/tty
    if [[ "$do_setup" =~ ^[Nn]$ ]]; then
        log_info "Skipping SSH configuration."
        return 0
    fi

    local ssh_email=""
    while [ -z "$ssh_email" ]; do
        printf "\r\033[K\033[1;34m[i]\033[0m Enter the email for SSH: " > /dev/tty
        read -r ssh_email < /dev/tty
    done

    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

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

# Configures global Git settings with the user name and email.
_setup_git() {
    local do_setup="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to configure Git? [Y/n]: " > /dev/tty
    read -r do_setup < /dev/tty
    if [[ "$do_setup" =~ ^[Nn]$ ]]; then
        log_info "Skipping Git configuration."
        return 0
    fi

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

# Sets the system timezone and enables NTP synchronization.
#
# Args:
#   timezone: The timezone to set (e.g., Europe/Paris).
_setup_time() {
    local do_setup="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to configure System Timezone? [Y/n]: " > /dev/tty
    read -r do_setup < /dev/tty
    if [[ "$do_setup" =~ ^[Nn]$ ]]; then
        log_info "Skipping Timezone configuration."
        return 0
    fi

    local tz="$1"
    log_info "Configuring system time for $tz..."
    sudo timedatectl set-timezone "$tz"
    sudo timedatectl set-ntp true
    sudo hwclock --systohc
}

# Creates symbolic links for all user dotfiles.
_setup_dotfiles() {
    local do_setup="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to deploy user dotfiles? [Y/n]: " > /dev/tty
    read -r do_setup < /dev/tty
    if [[ "$do_setup" =~ ^[Nn]$ ]]; then
        log_info "Skipping dotfiles deployment."
        return 0
    fi

    log_info "Setting up dotfiles (symlinks)..."

    local conf_dir="$HOME/.config"
    local repo="$SETUP_DIR"

    link_config "$repo/.config/hypr" "$conf_dir/hypr"
    link_config "$repo/.config/waybar" "$conf_dir/waybar"
    link_config "$repo/.config/wofi" "$conf_dir/wofi"
    link_config "$repo/.config/rofi" "$conf_dir/rofi"
    link_config "$repo/.config/mako" "$conf_dir/mako"
    link_config "$repo/.config/ghostty" "$conf_dir/ghostty"
    link_config "$repo/.config/fastfetch" "$conf_dir/fastfetch"
    link_config "$repo/.config/nvim" "$conf_dir/nvim"

    link_config "$repo/.config/zshrc" "$HOME/.zshrc"
    link_config "$repo/.config/vimrc" "$HOME/.vimrc"
    link_config "$repo/.config/ssh/config" "$HOME/.ssh/config"

    local starship="$repo/.config/starship/nerd-font-symbols.toml"
    link_config "$starship" "$conf_dir/starship.toml"

    log_info "Deploying wallpapers..."
    local wall_dir="$repo/.assets/wallpapers/"
    mkdir -p ~/Pictures/wallpapers/.active/
    cp $wall_dir/default/* "$HOME/Pictures/wallpapers"
    cp $wall_dir/active/* "$HOME/Pictures/wallpapers/.active"
}

# Entry point for the configuration module.
setup() {
    _setup_ssh_key

    run_task "Configuring Git Settings..." _setup_git
    run_task "Configuring System Timezone..." _setup_time "$CFG_TIMEZONE"
    run_task "Deploying User Dotfiles..." _setup_dotfiles
}
