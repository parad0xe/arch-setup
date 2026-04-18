#!/bin/bash

# Graphically select a wallpaper (image or mp4) and its destination.
_wall_selector() {
    local wall_dir="$HOME/Pictures/wallpapers"
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
    local rofi_list=""
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
    local full_path="$wall_dir/$img_choice"

    local type_choice=$(echo -e "desktop\nlock\nlogin" | rofi -dmenu -i -p "Apply to..." -theme "$theme")
    [ -z "$type_choice" ] && exit 0

    # 4. Execute application script
    bash "$script" "$full_path" "$type_choice"
}

_wall_selector
