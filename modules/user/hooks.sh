#!/bin/bash
# Hooks of modules/settings.toml, run by lib/hook.sh.

# Creates ~/.ssh/config.d, where the machine-specific hosts and keys go (not
# versioned, included by the SSH config), and keeps ~/.ssh private.
create_ssh_config_d() {
    mkdir -p "$HOME/.ssh/config.d"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/config.d"
}

# Generates an SSH ed25519 key, or an ed25519-sk key on a FIDO2 security key
# (INPUT_FIDO=1): downloaded from the security key when it holds one,
# generated on it otherwise. ssh-keygen asks for the PIN and the touch
# itself: the unit is attended.
#
# Inputs: INPUT_EMAIL, INPUT_FIDO, INPUT_PASSPHRASE.
generate_ssh_key() {
    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    log_info "Setting up an SSH key for $INPUT_EMAIL..."

    if [ "${INPUT_FIDO:-0}" = 1 ]; then
        local key_path="$ssh_dir/id_ed25519_sk"
        if ls "$key_path"* 1> /dev/null 2>&1; then
            log_warn "A FIDO2 SSH key already exists locally."
            return 0
        fi

        log_info "Plug the security key in; enter its PIN if asked, then touch it when it blinks."
        log_info "Looking for a resident key on the security key..."
        if (cd "$ssh_dir" && ssh-keygen -K); then
            log_success "Resident key retrieved from the security key."
            return 0
        fi

        log_warn "No resident key on the security key: generating one..."
        ssh-keygen -t ed25519-sk -O resident -O verify-required -C "$INPUT_EMAIL" -f "$key_path" -N "${INPUT_PASSPHRASE-}"
        return 0
    fi

    local key_path="$ssh_dir/id_ed25519"
    if [ -f "$key_path" ]; then
        log_warn "An SSH key already exists at $key_path."
        return 0
    fi

    log_info "Generating an ed25519 SSH key..."
    ssh-keygen -t ed25519 -C "$INPUT_EMAIL" -f "$key_path" -N "${INPUT_PASSPHRASE-}"
}

# Writes the Git name, email and default branch to ~/.gitconfig, read after
# the deployed ~/.config/git/config (named explicitly: --global would write
# into the deployed file when ~/.gitconfig does not exist yet).
#
# Inputs: INPUT_NAME, INPUT_EMAIL, INPUT_BRANCH.
setup_git() {
    log_info "Configuring the Git identity..."
    git config --file "$HOME/.gitconfig" user.name "$INPUT_NAME"
    git config --file "$HOME/.gitconfig" user.email "$INPUT_EMAIL"
    git config --file "$HOME/.gitconfig" init.defaultBranch "${INPUT_BRANCH:-main}"
}
