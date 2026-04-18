#!/bin/bash

active_dir="$HOME/Pictures/wallpapers/.active"

# Restores the desktop wallpaper at boot securely using awww.
_restore_desktop() {
    if ls "$active_dir"/desktop_active.mp4 1> /dev/null 2>&1; then
        killall awww-daemon 2>/dev/null
        killall mpvpaper 2>/dev/null
        mpvpaper -o "loop no-audio panscan=1.0 hwdec=auto" "*" "$active_dir/desktop_active.mp4" & disown
    else
        local img=$(find "$active_dir" -maxdepth 1 -name "desktop_active.*" | \
            grep -iE "\.(jpg|jpeg|png|webp)$" | head -n 1)

        if [ -n "$img" ]; then
            if ! pgrep -x awww-daemon > /dev/null; then
                awww-daemon --format xrgb &
            fi
            
            for i in {1..20}; do
                if awww query > /dev/null 2>&1; then 
                    sleep 0.1
                    break
                fi
                sleep 0.1
            done
            
            awww img "$img" --transition-type none
        fi
    fi
}

# Updates wallpapers using awww or mpvpaper depending on format.
_update_wallpaper() {
    local src="$1"
    local type="${2:-desktop}"
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
            rm -f "$active_dir/desktop_active."*
            
            if [ "$ext" = "mp4" ]; then
                cp "$src" "$active_dir/desktop_active.mp4"
                killall awww-daemon 2>/dev/null
                killall mpvpaper 2>/dev/null
                mpvpaper -o "loop no-audio panscan=1.0 hwdec=auto" "*" "$active_dir/desktop_active.mp4" & disown
            else
                local target="$active_dir/desktop_active.jpg"
                cp "$src" "$target"
                
                killall mpvpaper 2>/dev/null
                
                if ! pgrep -x awww-daemon > /dev/null; then
                    awww-daemon --format xrgb &
                fi

                for i in {1..20}; do
                    if awww query > /dev/null 2>&1; then break; fi
                    sleep 0.1
                done
                
                awww img "$target" --transition-type simple --transition-step 20 --transition-fps 60 & disown
            fi
            ;;
        "lock")
            cp "$process_src" "$active_dir/lock_active.jpg"
            notify-send "Wallpaper" "Lock screen background updated"
            ;;
        "login")
            local login_target="/usr/share/sddm/themes/tokyo-night-sddm/background.jpg"
            pkexec cp "$process_src" "$login_target"
            notify-send "Wallpaper" "Login screen background updated"
            ;;
    esac
}

if [ -z "$1" ]; then
    _restore_desktop
else
    _update_wallpaper "$1" "$2"
fi
