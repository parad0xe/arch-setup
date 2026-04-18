#!/bin/bash

set -e

# --- CONFIGURATION ---
# Remplace cette URL par l'URL réelle de ton dépôt Git.
REPO_URL="https://github.com/parad0xe/arch-setup.git"
TARGET_DIR="$HOME/.dotfiles"

# Prints an informational message to the standard output.
#
# Args:
#   msg: The message to display.
log_info() {
    printf "\033[1;34m[INFO]\033[0m %s\n" "$1"
}

log_info "Starting Arch Linux setup bootstrap..."

# 1. Installer Git si nécessaire
if ! command -v git &>/dev/null; then
    log_info "Installing Git..."
    sudo pacman -Sy --needed --noconfirm git
fi

if [ -d "$TARGET_DIR" ]; then
    log_info "Repository already exists at $TARGET_DIR. Updating..."
    cd "$TARGET_DIR"
    git pull
else
    log_info "Cloning repository to $TARGET_DIR..."
    git clone "$REPO_URL" "$TARGET_DIR"
fi

# 3. Lancer ton orchestrateur d'installation
log_info "Launching the main installation script..."
cd "$TARGET_DIR"
bash install.sh
