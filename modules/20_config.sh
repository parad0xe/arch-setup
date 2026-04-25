#!/bin/bash

# Generates an SSH ed25519 key for the provided email address.
#
# Args:
#   email: The email address for the SSH key.
_setup_ssh_key() {
    local email="$1"
    local key_path="$HOME/.ssh/id_ed25519"

    log_info "Setting up SSH key for $email..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"


    if [ -f "$key_path" ]; then
        log_warn "SSH key already exists at $key_path."
    else
		local passphrase
		getpass "Please enter your SSH passphrase (or press Enter for none):" passphrase
        ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N "$passphrase"
		unset passphrase
    fi
}

# Configures global Git settings with the user name and email.
#
# Args:
#   user: The Git username.
#   email: The Git email address.
_setup_git() {
    local user="$1"
    local email="$2"

    log_info "Configuring global Git settings..."
    git config --global user.name "$user"
    git config --global user.email "$email"
    git config --global init.defaultBranch main
}

# Sets the system timezone and enables NTP synchronization.
#
# Args:
#   timezone: The timezone to set.
_setup_time() {
    local tz="$1"

    log_info "Configuring system time for $tz..."
    sudo timedatectl set-timezone "$tz"
    sudo timedatectl set-ntp true
    sudo hwclock --systohc
}

# Creates symbolic links for all user dotfiles.
_setup_dotfiles() {
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
	run_task "Generating SSH Key..." _setup_ssh_key "$CFG_EMAIL"
    run_task "Configuring Git Settings..." _setup_git "$CFG_GIT_USER" "$CFG_EMAIL"
    run_task "Configuring System Timezone..." _setup_time "$CFG_TIMEZONE"
    run_task "Deploying User Dotfiles..." _setup_dotfiles
}
