#!/bin/bash

WALL_DIR="$HOME/Pictures/wallpapers/mp4"
THUMB_DIR="$WALL_DIR/.thumbnails"

# 1. Générer les miniatures manquantes
for video in "$WALL_DIR"/*.mp4; do
    [ -f "$video" ] || continue 
    
    filename=$(basename "$video")
    thumb="$THUMB_DIR/${filename%.mp4}.jpg"
    
    if [ ! -f "$thumb" ]; then
        ffmpegthumbnailer -i "$video" -o "$thumb" -s 512
    fi
done

ROFI_LIST=""
for video in "$WALL_DIR"/*.mp4; do
    [ -f "$video" ] || continue
    filename=$(basename "$video")
    thumb="$THUMB_DIR/${filename%.mp4}.jpg"
    
    ROFI_LIST+="${filename}\0icon\x1f${thumb}\n"
done

CHOICE=$(echo -e -n "$ROFI_LIST" | rofi -dmenu -i -p "Wallpapers" -show-icons)

if [ -n "$CHOICE" ]; then
    ~/Projects/arch-setup/dotfiles/hypr/change-wall.sh "$WALL_DIR/$CHOICE"
fi
