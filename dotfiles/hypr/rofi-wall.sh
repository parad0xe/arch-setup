#!/bin/bash

WALL_DIR="$HOME/Pictures/wallpapers"
THUMB_DIR="$WALL_DIR/.thumbnails"
mkdir -p "$THUMB_DIR"

for video in "$WALL_DIR"/*.mp4; do
    [ -f "$video" ] || continue 
    filename=$(basename "$video")
    thumb="$THUMB_DIR/${filename%.mp4}.jpg"
    if [ ! -f "$thumb" ]; then
        ffmpegthumbnailer -i "$video" -o "$thumb" -s 512
    fi
done

ROFI_LIST=""
for file in "$WALL_DIR"/*; do
    [ -f "$file" ] || continue
    filename=$(basename "$file")
    
    ext="${filename##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    if [ "$ext" = "mp4" ]; then
        thumb="$THUMB_DIR/${filename%.mp4}.jpg"
        ROFI_LIST+="${filename}\0icon\x1f${thumb}\n"
    elif [[ "$ext" =~ ^(jpg|jpeg|png|webp)$ ]]; then
        ROFI_LIST+="${filename}\0icon\x1f${file}\n"
    fi
done

CHOICE=$(echo -e -n "$ROFI_LIST" | rofi -dmenu -i -p "Wallpapers" -show-icons)

if [ -n "$CHOICE" ]; then
    ~/.config/hypr/change-wall.sh "$WALL_DIR/$CHOICE"
fi
