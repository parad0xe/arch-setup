#!/bin/bash
# Adjusts the opacity of the focused window by a step. Usage: opacity.sh up|down|reset
step=0.05; min=0.25; max=1.0

case "$1" in up|down|reset) ;; *) echo "usage: $0 up|down|reset" >&2; exit 1 ;; esac

info=$(hyprctl activewindow -j)
addr=$(grep -o '"address": "0x[0-9a-f]*"' <<<"$info" | head -1 | cut -d'"' -f4)
[ -n "$addr" ] || exit 0   # nothing focused

cur=$(hyprctl getprop "address:$addr" opacity 2>/dev/null)
case "$cur" in ''|*[!0-9.]*) cur=1 ;; esac

new=$(awk -v c="$cur" -v d="$1" -v s="$step" -v mn="$min" -v mx="$max" 'BEGIN {
    v = c
    if (d == "up") v = c + s; else if (d == "down") v = c - s; else v = 1
    if (v > mx) v = mx; if (v < mn) v = mn
    printf "%.2f", v
}')

[ "$new" != "$cur" ] || exit 0
for prop in opacity opacity_fullscreen; do
    hyprctl eval "hl.dispatch(hl.dsp.window.set_prop({ prop = \"$prop\", value = \"$new\" }))" > /dev/null
done
