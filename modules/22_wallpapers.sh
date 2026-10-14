#!/bin/bash

# Asks for the git repository holding the wallpapers (CFG_WALLPAPERS_REPO by
# default) and copies the formats the wallpaper selector shows into
# ~/Pictures/wallpapers, keeping the repository's sub-folders.
_deploy_wallpapers() {
    local do_setup="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to deploy wallpapers? [Y/n]: " > /dev/tty
    read -r do_setup < /dev/tty
    if [[ "$do_setup" =~ ^[Nn]$ ]]; then
        log_info "Skipping wallpapers deployment."
        return 0
    fi

    local repo=""
    printf "\r\033[K\033[1;34m[i]\033[0m Wallpapers repository [%s]: " "$CFG_WALLPAPERS_REPO" > /dev/tty
    read -r repo < /dev/tty
    repo="${repo:-$CFG_WALLPAPERS_REPO}"

    local clone_dir
    clone_dir=$(mktemp -d)

    log_info "Cloning $repo..."
    # Fails instead of asking for credentials (GitHub answers a mistyped
    # repository URL as if it were private)
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$repo" "$clone_dir"; then
        log_warn "Could not clone $repo, run ./setup.sh -m wallpapers to retry."
        rm -rf "$clone_dir"
        return 0
    fi

    local dest="$HOME/Pictures/wallpapers"
    log_info "Copying wallpapers to ${dest/#$HOME/\~}..."
    mkdir -p "$dest"
    (
        cd "$clone_dir" || exit
        find . -path ./.git -prune -o -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
            -o -iname "*.webp" -o -iname "*.mp4" \
        \) -exec cp --parents {} "$dest" \;
    )

    rm -rf "$clone_dir"
}

# Entry point for the wallpapers module.
setup() {
    run_task "Deploying Wallpapers..." _deploy_wallpapers
}
