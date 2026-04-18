#!/bin/bash

STATE_FILE="$HOME/.current_wallpaper"

if [ -n "$1" ]; then
    echo "$1" > "$STATE_FILE"
    WALLPAPER="$1"
else
    if [ -f "$STATE_FILE" ]; then
        WALLPAPER=$(cat "$STATE_FILE")
    else
        exit 0
    fi
fi

EXT="${WALLPAPER##*.}"
EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

if [ "$EXT" = "mp4" ]; then
    killall swww-daemon 2>/dev/null # Coupe le gestionnaire d'images
    killall mpvpaper 2>/dev/null    # Relance proprement la vidéo
    
    mpvpaper -o "loop no-audio panscan=1.0 hwdec=auto" "*" "$WALLPAPER" & disown

elif [[ "$EXT" =~ ^(jpg|jpeg|png|webp)$ ]]; then
    killall mpvpaper 2>/dev/null    # Coupe la vidéo
    
    if ! pgrep -x swww-daemon > /dev/null; then
        swww-daemon &
        sleep 0.5
    fi
    
    swww img "$WALLPAPER" --transition-type any --transition-fps 60 & disown
fi
