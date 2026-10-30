#!/bin/bash
# Hooks of modules/wallpapers.toml, run by lib/hook.sh.

WALLPAPERS_DIR="$HOME/Pictures/wallpapers"

# Clones the wallpapers repository and copies the formats the wallpaper
# selector shows into the wallpapers folder, keeping its sub-folders.
#
# Inputs: INPUT_REPO.
deploy_wallpapers() {
    local clone_dir
    clone_dir=$(mktemp -d)

    log_info "Cloning $INPUT_REPO..."
    # Fails instead of asking for credentials (GitHub answers a mistyped
    # repository URL as if it were private)
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$INPUT_REPO" "$clone_dir"; then
        rm -rf "$clone_dir"
        log_error "Could not clone $INPUT_REPO."
        return 1
    fi

    log_info "Copying the wallpapers to ${WALLPAPERS_DIR/#$HOME/\~}..."
    mkdir -p "$WALLPAPERS_DIR"
    (
        cd "$clone_dir" || exit
        find . -path ./.git -prune -o -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
            -o -iname "*.webp" -o -iname "*.mp4" \
        \) -exec cp --parents {} "$WALLPAPERS_DIR" \;
    )

    rm -rf "$clone_dir"
}

# Lets the user pick a wallpaper of the wallpapers folder with fzf, next to
# a preview of the image, and prints its path (nothing when Esc is pressed).
#
# Args:
#   context: What the wallpaper is for (Desktop, All, Lock), shown as title.
#   targets: Where it will be applied, shown under the search field.
#   videos: "videos" to also list the mp4 files.
_pick_wallpaper() {
    local context="$1" targets="$2"
    local types=(-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp")
    if [ "${3-}" = "videos" ]; then
        types+=(-o -iname "*.mp4")
    fi
    local border="rounded"
    if [ "$UI_UNICODE" != 1 ]; then
        border="sharp"
    fi

    # One "path<TAB>shown name" line per wallpaper, outside the hidden
    # folders of the wallpaper scripts (.active, .thumbnails)
    # shellcheck disable=SC2016  # fzf expands {1} in its preview command
    find "$WALLPAPERS_DIR" -path "$WALLPAPERS_DIR/.*" -prune -o -type f \( "${types[@]}" \) \
        -printf '%p\t%P\n' \
        | sort -t $'\t' -k 2 \
        | fzf --delimiter '\t' --with-nth 2 --layout reverse \
            --border "$border" --border-label " $context " \
            --prompt "$context > " --header "Applied to: $targets (Esc to skip)" \
            --preview 'case {1} in
                *.mp4|*.MP4) echo "Video (no preview)" ;;
                *) chafa --size "${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}" {1} ;;
            esac' \
        | cut -f 1
}

# Picks the default wallpapers, the same one everywhere or one per screen,
# and stores them where the wallpaper selector does: desktop (image or
# video, on every monitor), lock screen and SDDM login screen (images). The
# desktop one is applied right away when the setup runs inside Hyprland.
#
# Inputs: INPUT_SAME (1 for the same wallpaper everywhere).
choose_default_wallpapers() {
    if [ -z "$(find "$WALLPAPERS_DIR" -path "$WALLPAPERS_DIR/.*" -prune -o -type f -print -quit 2> /dev/null)" ]; then
        log_info "No wallpaper in ${WALLPAPERS_DIR/#$HOME/\~}, no default to pick."
        return 0
    fi

    local desktop lock login
    if [ "${INPUT_SAME:-1}" = 1 ]; then
        desktop=$(_pick_wallpaper "All" "desktop, lock and login screens")
        lock="$desktop"
        login="$desktop"
    else
        desktop=$(_pick_wallpaper "Desktop" "desktop" videos)
        lock=$(_pick_wallpaper "Lock" "lock screen")
        login=$(_pick_wallpaper "Login" "login screen")
    fi

    local active_dir="$WALLPAPERS_DIR/.active"
    mkdir -p "$active_dir"

    if [ -n "$desktop" ]; then
        # Also drops the per-monitor wallpapers, so it shows on every monitor
        rm -f "$active_dir"/desktop_active.* "$active_dir"/desktop_active__*
        if [[ "${desktop,,}" == *.mp4 ]]; then
            cp "$desktop" "$active_dir/desktop_active.mp4"
        else
            cp "$desktop" "$active_dir/desktop_active.jpg"
        fi
        log_success "Desktop wallpaper: ${desktop#"$WALLPAPERS_DIR"/}"

        local change_wall="$HOME/.config/hypr/scripts/change-wall.sh"
        if [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ] && [ -x "$change_wall" ]; then
            "$change_wall" > /dev/null 2>&1 || true
        fi
    fi

    if [ -n "$lock" ] && [[ "${lock,,}" != *.mp4 ]]; then
        cp "$lock" "$active_dir/lock_active.jpg"
        log_success "Lock screen wallpaper: ${lock#"$WALLPAPERS_DIR"/}"
    fi

    if [ -n "$login" ] && [[ "${login,,}" != *.mp4 ]]; then
        local sddm_dir="/usr/share/sddm/themes/tokyo-night-sddm"
        if [ -d "$sddm_dir" ]; then
            sudo cp "$login" "$sddm_dir/background.jpg"
            sudo chmod 644 "$sddm_dir/background.jpg"
            log_success "Login screen wallpaper: ${login#"$WALLPAPERS_DIR"/}"
        else
            log_warn "SDDM theme not installed, skipping the login screen wallpaper."
        fi
    fi
}
