#!/bin/bash

set -e

export SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ASSETS_DIR="$SETUP_DIR/assets"

# --- CONFIGURATION GLOBALE ---
export CFG_TIMEZONE="Europe/Paris"
export CFG_LOCK_BG_IMG="$SETUP_DIR/.config/hypr/wallpapers/lock_background.jpg"
export CFG_EMAIL="parad0xe@protonmail.com"
export CFG_GIT_USER="parad0xe"

# Source modules and automatically execute their setup functions.
# target_dir: absolute path to the modules directory
load_and_run_modules() {
    local target_dir="$1"
    local module_name
    local func_name

    for module in "$target_dir"/*.sh; do
	if [ -f "$module" ]; then
	    unset -f setup 2>/dev/null

	    source "$module"

	    module_name=$(basename "$module" .sh | sed 's/^[0-9]*_//')

	    if declare -f setup > /dev/null; then
		setup
		unset -f setup
	    else
		log_error "Function 'setup' not found in $(basename "$module")"
	    fi
	fi
    done
}

# Main orchestration function for the setup process.
main() {
    load_and_run_modules "$SETUP_DIR/modules"

    sleep 0.5
    log_info "Setup completed successfully! Please reboot."
}

main
