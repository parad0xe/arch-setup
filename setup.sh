#!/bin/bash

set -e

export SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ASSETS_DIR="$SETUP_DIR/assets"

# --- CONFIGURATION GLOBALE ---
export CFG_TIMEZONE="Europe/Paris"
export CFG_LOCK_BG_IMG="$SETUP_DIR/.assets/wallpapers/active/lock_active.jpg"
export CFG_EMAIL="parad0xe@protonmail.com"
export CFG_GIT_USER="parad0xe"

# Prints the help message and exits.
_show_help() {
    echo "Usage: ./setup.sh [options]"
    echo ""
    echo "Options:"
    echo "  -l, --list            List all available modules"
    echo "  -m, --module <name>   Run only a specific module (e.g., dev)"
    echo "  -r, --resume <name>   Resume installation from a specific module"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh --list"
    echo "  ./setup.sh -m graphical"
    echo "  ./setup.sh --resume dev"
    exit 0
}

# Main orchestration function for the setup process.
#
# Args:
#   @: Command line arguments.
main() {
    local mode="all"
    local target=""

    # Corrected argument parsing
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -l|--list) mode="list"; shift ;;
            -m|--module) mode="module"; target="$2"; shift 2 ;;
            -r|--resume) mode="resume"; target="$2"; shift 2 ;;
            -h|--help) _show_help ;;
            *) echo "Unknown parameter: $1"; exit 1 ;;
        esac
    done

    # --- LIST MODE ---
    if [ "$mode" = "list" ]; then
        echo -e "\n\033[1;34m[i]\033[0m Available modules in $SETUP_DIR/modules:\n"
        for mod in "$SETUP_DIR"/modules/[0-9][0-9]_*.sh; do
            local mod_name=$(basename "$mod" .sh)
            local clean_name="${mod_name#*_}"
            
            if [ "$mod_name" = "00_core" ]; then
				printf "  \033[2m%-15s (Core framework - auto-loaded)\033[0m\n" "$mod_name"
            else
                printf "  \033[1;32m%-15s\033[0m (Use: ./setup.sh -m \033[1;36m%s\033[0m)\n" "$mod_name" "$clean_name"
            fi
        done
        echo ""
        exit 0
    fi

    # --- EXECUTION MODE ---
    
    # Load core module first to initialize UI and logging
    source "$SETUP_DIR/modules/00_core.sh"
    setup

    local skip=false
    if [ "$mode" = "resume" ]; then
        skip=true
    fi

    # Find and execute modules in alphabetical order
    for mod in "$SETUP_DIR"/modules/[0-9][0-9]_*.sh; do
        # Skip core module since it is already loaded
        if [[ "$(basename "$mod")" == "00_core.sh" ]]; then
            continue
        fi

        local mod_name=$(basename "$mod" .sh)
        local clean_name="${mod_name#*_}"
        
        if [ "$mode" = "module" ]; then
            if [ "$clean_name" = "$target" ] || [ "$mod_name" = "$target" ]; then
                log_info "Running specific module: $mod_name"
                unset -f setup 2>/dev/null
                source "$mod"
                if declare -f setup > /dev/null; then setup; fi
                break
            fi
        elif [ "$mode" = "resume" ]; then
            if [ "$clean_name" = "$target" ] || [ "$mod_name" = "$target" ]; then
                skip=false
                log_info "Resuming from module: $mod_name"
            fi
            
            if [ "$skip" = false ]; then
                unset -f setup 2>/dev/null
                source "$mod"
                if declare -f setup > /dev/null; then setup; fi
            fi
        else
            unset -f setup 2>/dev/null
            source "$mod"
            if declare -f setup > /dev/null; then setup; fi
        fi
    done

    sleep 0.5
    log_success "Setup completed successfully! Please reboot."
}

main "$@"
