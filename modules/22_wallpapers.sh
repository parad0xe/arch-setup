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

# Installs fzf and chafa, which shows the images in the terminal.
_install_wallpaper_picker() {
    install_pkg "fzf"
    install_pkg "chafa"
}

# Lets the user pick a wallpaper of ~/Pictures/wallpapers with fzf, next to
# a preview of the image, and prints its path (nothing when Esc is pressed).
#
# Args:
#   context: What the wallpaper is for (Desktop, All, Lock), shown as title.
#   targets: Where it will be applied, shown under the search field.
#   videos: "videos" to also list the mp4 files.
_pick_wallpaper() {
    local context="$1"
    local targets="$2"
    local wall_dir="$HOME/Pictures/wallpapers"

    local types=(-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp")
    if [ "$3" = "videos" ]; then
        types+=(-o -iname "*.mp4")
    fi

    # One "path<TAB>shown name" line per wallpaper, outside the hidden
    # folders of the wallpaper scripts (.active, .thumbnails)
    find "$wall_dir" -path "$wall_dir/.*" -prune -o -type f \( "${types[@]}" \) \
        -printf '%p\t%P\n' \
        | sort -t $'\t' -k 2 \
        | fzf --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " $context " \
            --prompt "$context > " --header "Applied to: $targets (Esc to skip)" \
            --preview 'case {1} in
                *.mp4|*.MP4) echo "Video (no preview)" ;;
                *) chafa --size "${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}" {1} ;;
            esac' \
        | cut -f 1
}

# Asks for the wallpapers applied by default, the same one everywhere or one
# per screen, and stores them where the wallpaper selector does: desktop
# (image or video, on every monitor), lock screen and SDDM login screen
# (images).
_choose_default_wallpapers() {
    local wall_dir="$HOME/Pictures/wallpapers"
    local active_dir="$wall_dir/.active"
    local sddm_dir="/usr/share/sddm/themes/tokyo-night-sddm"

    if [ -z "$(find "$wall_dir" -path "$wall_dir/.*" -prune -o -type f -print -quit 2>/dev/null)" ]; then
        log_info "No wallpaper in ${wall_dir/#$HOME/\~}, skipping default wallpapers."
        return 0
    fi

    local do_setup="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Do you want to choose the default wallpapers? [Y/n]: " > /dev/tty
    read -r do_setup < /dev/tty
    if [[ "$do_setup" =~ ^[Nn]$ ]]; then
        log_info "Skipping default wallpapers."
        return 0
    fi

    run_task "Installing Wallpaper Picker..." _install_wallpaper_picker

    local same="y"
    printf "\r\033[K\033[1;34m[i]\033[0m Same wallpaper for the desktop, lock and login screens? (n: one each, needed for a video desktop) [Y/n]: " > /dev/tty
    read -r same < /dev/tty

    local desktop lock login
    if [[ "$same" =~ ^[Nn]$ ]]; then
        desktop=$(_pick_wallpaper "Desktop" "desktop" videos)
        lock=$(_pick_wallpaper "Lock" "lock screen")
        login=$(_pick_wallpaper "Login" "login screen")
    else
        desktop=$(_pick_wallpaper "All" "desktop, lock and login screens")
        lock="$desktop"
        login="$desktop"
    fi

    mkdir -p "$active_dir"

    if [ -n "$desktop" ]; then
        # Also drops the per-monitor wallpapers, so it shows on every monitor
        rm -f "$active_dir"/desktop_active.* "$active_dir"/desktop_active__*
        if [[ "${desktop,,}" == *.mp4 ]]; then
            cp "$desktop" "$active_dir/desktop_active.mp4"
        else
            cp "$desktop" "$active_dir/desktop_active.jpg"
        fi
        log_success "Desktop wallpaper: ${desktop#"$wall_dir"/}"

        # Applies it right away when the setup runs inside Hyprland
        local change_wall="$HOME/.config/hypr/scripts/change-wall.sh"
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -x "$change_wall" ]; then
            "$change_wall" > /dev/null 2>&1
        fi
    fi

    if [ -n "$lock" ]; then
        cp "$lock" "$active_dir/lock_active.jpg"
        log_success "Lock screen wallpaper: ${lock#"$wall_dir"/}"
    fi

    if [ -n "$login" ]; then
        if [ -d "$sddm_dir" ]; then
            sudo cp "$login" "$sddm_dir/background.jpg"
            sudo chmod 644 "$sddm_dir/background.jpg"
            log_success "Login screen wallpaper: ${login#"$wall_dir"/}"
        else
            log_warn "SDDM theme not installed, skipping the login screen wallpaper."
        fi
    fi
}

# Entry point for the wallpapers module.
setup() {
    run_task "Deploying Wallpapers..." _deploy_wallpapers
    _choose_default_wallpapers
}
