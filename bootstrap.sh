#!/bin/bash

set -e

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.dotfiles"

# Prints an informational message to the standard output.
#
# Args:
#   msg: The message to display.
log_info() {
    printf "\033[1;34m[INFO]\033[0m %s\n" "$1"
}

log_info "Starting Arch Linux setup bootstrap..."

if ! command -v git &>/dev/null; then
    log_info "Installing Git..."
    sudo pacman -Sy --needed --noconfirm git
fi

if [ -d "$TARGET_DIR" ]; then
    log_info "Repository already exists at $TARGET_DIR. Updating..."
    cd "$TARGET_DIR"
    git pull
else
    log_info "Moving the repository to $TARGET_DIR..."
	mv $SETUP_DIR $TARGET_DIR
fi

log_info "Launching the main installation script..."
cd "$TARGET_DIR"
sleep 3
bash install.sh
