#!/bin/bash

active_dir="$HOME/Pictures/wallpapers/.active"

# Returns all currently connected monitor names, one per line.
_monitor_names() {
    hyprctl monitors | awk '/^Monitor/ {print $2}'
}

# Succeeds if at least one of the given paths is an existing file.
_any_file() {
    local f
    for f in "$@"; do
        [ -f "$f" ] && return 0
    done
    return 1
}

# Re-applies every stored desktop wallpaper (global + per-monitor overrides)
# to the currently connected monitors. Used both at boot and after any change.
#
# Args:
#   transition: awww transition type for images (default: none).
_apply_all_desktop() {
    local transition="${1:-none}"

    mkdir -p "$active_dir"

    local has_video=false
    local has_image=false
    _any_file "$active_dir"/desktop_active.mp4 "$active_dir"/desktop_active__*.mp4 && has_video=true
    _any_file "$active_dir"/desktop_active.jpg "$active_dir"/desktop_active__*.jpg && has_image=true

    # The image daemon keeps running between image changes so they get a
    # transition; it is restarted whenever a video shares the background.
    killall mpvpaper 2>/dev/null
    if [ "$has_video" = true ] || [ "$has_image" = false ]; then
        killall awww-daemon 2>/dev/null
    fi

    # Figure out which monitors have a per-output override (image or video).
    declare -A override
    for f in "$active_dir"/desktop_active__*; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
        name="${name#desktop_active__}"
        name="${name%.*}"
        override[$name]=1
    done

    # Start per-monitor video overrides.
    for f in "$active_dir"/desktop_active__*.mp4; do
        [ -f "$f" ] || continue
        local name=$(basename "$f" .mp4)
        name="${name#desktop_active__}"
        mpvpaper -o "loop no-audio panscan=1.0 hwdec=auto" "$name" "$f" & disown
    done

    # Start the global video (applies to any monitor without its own override).
    if [ -f "$active_dir/desktop_active.mp4" ]; then
        for m in $(_monitor_names); do
            [ -n "${override[$m]}" ] && continue
            mpvpaper -o "loop no-audio panscan=1.0 hwdec=auto" "$m" "$active_dir/desktop_active.mp4" & disown
        done
    fi

    if [ "$has_image" = true ]; then
        if ! pgrep -x awww-daemon > /dev/null; then
            awww-daemon --format xrgb &
        fi

        for i in {1..20}; do
            if awww query > /dev/null 2>&1; then break; fi
            sleep 0.1
        done

        local awww_opts=(--transition-type "$transition" --transition-step 20 --transition-fps 60)

        # Per-monitor image overrides.
        for f in "$active_dir"/desktop_active__*.jpg; do
            [ -f "$f" ] || continue
            local name=$(basename "$f" .jpg)
            name="${name#desktop_active__}"
            awww img "$f" --outputs "$name" "${awww_opts[@]}" & disown
        done

        # Global image, applied only to monitors without their own override.
        if [ -f "$active_dir/desktop_active.jpg" ]; then
            for m in $(_monitor_names); do
                [ -n "${override[$m]}" ] && continue
                awww img "$active_dir/desktop_active.jpg" --outputs "$m" "${awww_opts[@]}" & disown
            done
        fi
    fi
}

# Updates wallpapers using awww or mpvpaper depending on format.
#
# Args:
#   src: The source image or mp4 file.
#   type: desktop, lock, login or all of them (default: desktop).
#   monitor: Monitor name for a desktop wallpaper, or all (default: all).
_update_wallpaper() {
    local src="$1"
    local type="${2:-desktop}"
    local monitor="${3:-all}"
    local ext="${src##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    mkdir -p "$active_dir"

    local process_src="$src"
    if [ "$ext" = "mp4" ] && [ "$type" != "desktop" ]; then
        local filename=$(basename "$src")
        process_src="$HOME/Pictures/wallpapers/.thumbnails/${filename%.mp4}.jpg"
        if [ ! -f "$process_src" ]; then
            ffmpegthumbnailer -i "$src" -o "$process_src" -s 1080
        fi
    fi

    case "$type" in
        "desktop")
            local base="$active_dir/desktop_active"
            if [ -n "$monitor" ] && [ "$monitor" != "all" ]; then
                base="$active_dir/desktop_active__${monitor}"
            fi

            rm -f "${base}.mp4" "${base}.jpg"

            if [ "$ext" = "mp4" ]; then
                cp "$src" "${base}.mp4"
            else
                cp "$src" "${base}.jpg"
            fi

            _apply_all_desktop simple
            ;;
        "lock")
            cp "$process_src" "$active_dir/lock_active.jpg"
            notify-send "Wallpaper" "Lock screen background updated"
            ;;
        "login")
            local login_target="/usr/share/sddm/themes/tokyo-night-sddm/background.jpg"
            if pkexec cp "$process_src" "$login_target"; then
                notify-send "Wallpaper" "Login screen background updated"
            fi
            ;;
        "all")
            _update_wallpaper "$src" desktop all
            _update_wallpaper "$src" lock
            _update_wallpaper "$src" login
            ;;
    esac
}

if [ -z "$1" ]; then
    _apply_all_desktop
else
    _update_wallpaper "$1" "$2" "$3"
fi
