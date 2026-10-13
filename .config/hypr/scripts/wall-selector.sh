#!/bin/bash

# The wallpaper directory always starts here on a fresh run; "Change
# Directory" only overrides it for the current session, it is never saved.
_default_wall_dir="$HOME/Pictures/wallpapers"

# Prompts for a directory (free text, no suggestions). Echoes the chosen
# path on success. Returns 1 if the user cancelled or the path was invalid.
_change_wall_dir() {
    local current="$1"
    local theme="$HOME/.config/rofi/wallpaper.rasi"

    local new_dir="$HOME"
    new_dir=$(rofi -dmenu -p "Wallpaper directory" \
        -filter "$HOME" \
        -mesg "Current: $current" -theme "$theme" < /dev/null)
    [ -z "$new_dir" ] && return 1

    # Expand leading ~ and strip a trailing slash.
    new_dir="${new_dir/#\~/$HOME}"
    new_dir="${new_dir%/}"

    if [ ! -d "$new_dir" ]; then
        notify-send "Wallpaper" "Directory not found: $new_dir"
        return 1
    fi

    echo "$new_dir"
    return 0
}

# Graphically select a wallpaper (image or mp4) and its destination.
# Optional $1: wallpaper directory to use for this run (defaults to
# _default_wall_dir if not given).
_wall_selector() {
    local wall_dir="${1:-$_default_wall_dir}"
    local thumb_dir="$wall_dir/.thumbnails"
    local script="$HOME/.config/hypr/scripts/change-wall.sh"
	local theme="$HOME/.config/rofi/wallpaper.rasi"

    mkdir -p "$thumb_dir"

    # 1. Generate thumbnails for mp4 files
    for video in "$wall_dir"/*.mp4; do
        [ -f "$video" ] || continue 
        local filename=$(basename "$video")
        local thumb="$thumb_dir/${filename%.mp4}.jpg"
        if [ ! -f "$thumb" ]; then
            ffmpegthumbnailer -i "$video" -o "$thumb" -s 512
        fi
    done

    # 2. Build the list for Rofi
    local rofi_list="📁 Change Directory\0icon\x1ffolder\n"
    for file in "$wall_dir"/*; do
        [ -f "$file" ] || continue
        local filename=$(basename "$file")
        local ext=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')

        if [ "$ext" = "mp4" ]; then
            local thumb="$thumb_dir/${filename%.mp4}.jpg"
            rofi_list+="${filename}\0icon\x1f${thumb}\n"
        elif [[ "$ext" =~ ^(jpg|jpeg|png|webp)$ ]]; then
            rofi_list+="${filename}\0icon\x1f${file}\n"
        fi
    done

    # 3. Prompt user
    local img_choice=$(echo -e -n "$rofi_list" | rofi -dmenu -i -p "Wallpaper" -show-icons -theme "$theme")
    [ -z "$img_choice" ] && exit 0

    # Handle the "change directory" pseudo-entry, then restart the selector
    # using the picked directory for this run only.
    if [ "$img_choice" = "📁 Change Directory" ]; then
        local new_dir
        new_dir=$(_change_wall_dir "$wall_dir")
        if [ -n "$new_dir" ]; then
            _wall_selector "$new_dir"
        else
            _wall_selector "$wall_dir"
        fi
        return
    fi

    local full_path="$wall_dir/$img_choice"

    local type_choice=$(echo -e "desktop\nlock\nlogin" | rofi -dmenu -i -p "Apply to..." -theme "$theme")
    [ -z "$type_choice" ] && exit 0

    # 4. If setting a desktop wallpaper, ask which monitor it should apply to.
    local monitor="all"
    if [ "$type_choice" = "desktop" ]; then
        local monitor_names=$(hyprctl monitors | awk '/^Monitor/ {print $2}')
        local mon_list="All Monitors\n${monitor_names}"
        local mon_choice=$(echo -e "$mon_list" | rofi -dmenu -i -p "Apply to monitor" -theme "$theme")
        [ -z "$mon_choice" ] && exit 0
        if [ "$mon_choice" != "All Monitors" ]; then
            monitor="$mon_choice"
        fi
    fi

    # 5. Execute application script
    bash "$script" "$full_path" "$type_choice" "$monitor"
}

_wall_selector
