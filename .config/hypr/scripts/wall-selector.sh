#!/bin/bash

# The wallpaper directory always starts here on a fresh run; browsing to
# another folder only changes it for the current session, it is never saved.
_default_wall_dir="$HOME/Pictures/wallpapers"
_theme="$HOME/.config/rofi/wallpaper.rasi"
_change_wall="$HOME/.config/hypr/scripts/change-wall.sh"

_folder_entry="📁  Change folder…"
_parent_entry="⬆  Parent folder"
_path_entry="⌨  Type a path…"
_folder_prefix="📁  "

# Shows a text-only rofi menu (one column, no thumbnails).
#
# Args:
#   prompt: The menu prompt.
#   ...: Additional rofi arguments.
_text_menu() {
    local prompt="$1"
    shift
    rofi -dmenu -i -p "$prompt" -theme "$_theme" \
        -theme-str 'listview { columns: 1; lines: 6; }' "$@"
}

# Shows the wallpapers of a folder, after a "Change folder" entry.
# Echoes the selected entry, or nothing if cancelled.
#
# Args:
#   dir: The folder to show.
_wallpaper_grid() {
    local dir="$1"
    local thumb_dir="$dir/.thumbnails"

    # Generate thumbnails for mp4 files
    local video
    for video in "$dir"/*.mp4; do
        [ -f "$video" ] || continue
        local filename=$(basename "$video")
        local thumb="$thumb_dir/${filename%.mp4}.jpg"
        if [ ! -f "$thumb" ]; then
            mkdir -p "$thumb_dir"
            ffmpegthumbnailer -i "$video" -o "$thumb" -s 512 > /dev/null 2>&1
        fi
    done

    local list="${_folder_entry}\0icon\x1ffolder\n"
    local file
    for file in "$dir"/*; do
        [ -f "$file" ] || continue
        local filename=$(basename "$file")
        local ext=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')

        if [ "$ext" = "mp4" ]; then
            list+="${filename}\0icon\x1f${thumb_dir}/${filename%.mp4}.jpg\n"
        elif [[ "$ext" =~ ^(jpg|jpeg|png|webp)$ ]]; then
            list+="${filename}\0icon\x1f${file}\n"
        fi
    done

    echo -e -n "$list" | rofi -dmenu -i -p "Wallpaper  ${dir/#$HOME/\~}" \
        -show-icons -theme "$_theme"
}

# Asks for a folder path, prefilled with the current one.
# Echoes the folder on success, returns 1 if cancelled or not found.
#
# Args:
#   current: The folder currently shown.
_ask_path() {
    local current="$1"

    local path
    path=$(_text_menu "Folder" -filter "${current/#$HOME/\~}/" < /dev/null)
    [ -z "$path" ] && return 1

    path="${path/#\~/$HOME}"
    path="${path%/}"
    path="${path:-/}"

    if [ ! -d "$path" ]; then
        notify-send "Wallpaper" "Folder not found: $path"
        return 1
    fi

    echo "$path"
}

# Asks which folder to show next: the parent, a sub-folder or a typed path.
# Echoes the folder, returns 1 if cancelled.
#
# Args:
#   dir: The folder currently shown.
_choose_folder() {
    local dir="$1"

    local entries=""
    if [ "$dir" != "/" ]; then
        entries+="${_parent_entry}\n"
    fi

    local sub
    for sub in "$dir"/*/; do
        [ -d "$sub" ] || continue
        entries+="${_folder_prefix}$(basename "$sub")\n"
    done
    entries+="${_path_entry}"

    local choice
    choice=$(echo -e "$entries" | _text_menu "Folder  ${dir/#$HOME/\~}")

    case "$choice" in
        "$_parent_entry") dirname "$dir" ;;
        "$_path_entry") _ask_path "$dir" ;;
        "$_folder_prefix"*) echo "${dir%/}/${choice#"$_folder_prefix"}" ;;
        *) return 1 ;;
    esac
}

# Asks where to apply the wallpaper. Monitors are only listed when more than
# one is connected. Echoes "<type> <monitor>", or nothing if cancelled.
_choose_target() {
    local monitors
    monitors=$(hyprctl monitors | awk '/^Monitor/ {print $2}')

    local entries="Desktop (all monitors)"
    if [ "$(echo "$monitors" | wc -l)" -gt 1 ]; then
        local m
        for m in $monitors; do
            entries+="\nDesktop: $m"
        done
    fi
    entries+="\nLock screen\nLogin screen"

    local target
    target=$(echo -e "$entries" | _text_menu "Apply to")

    case "$target" in
        "Desktop (all monitors)") echo "desktop all" ;;
        "Desktop: "*) echo "desktop ${target#Desktop: }" ;;
        "Lock screen") echo "lock all" ;;
        "Login screen") echo "login all" ;;
    esac
}

# Browses folders and applies the selected wallpaper (image or mp4).
# Escape in the "Apply to" menu goes back to the wallpapers.
_wall_selector() {
    local wall_dir="$_default_wall_dir"

    while true; do
        local choice
        choice=$(_wallpaper_grid "$wall_dir")
        [ -z "$choice" ] && exit 0

        if [ "$choice" = "$_folder_entry" ]; then
            local new_dir
            if new_dir=$(_choose_folder "$wall_dir"); then
                wall_dir="$new_dir"
            fi
            continue
        fi

        local target type monitor
        target=$(_choose_target)
        [ -z "$target" ] && continue
        read -r type monitor <<< "$target"

        bash "$_change_wall" "$wall_dir/$choice" "$type" "$monitor"
        exit 0
    done
}

_wall_selector
