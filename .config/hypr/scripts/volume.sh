#!/bin/bash

# Adjust system volume via WirePlumber and send a synchronized notification.
# action: the operation to perform ("up", "down", or "mute")
manage_volume() {
	local action="$1"
	
	case "$action" in
		up)
			wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
			;;
		down)
			wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
			;;
		mute)
			wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
			;;
	esac

	# Récupération du niveau actuel
	local vol_status=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
	# Conversion de 0.50 en 50
	local vol_level=$(echo "$vol_status" | awk '{printf "%.0f\n", $2 * 100}')

	if echo "$vol_status" | grep -q "MUTED"; then
		notify-send -t 1500 -h string:x-canonical-private-synchronous:volume "Volume muted"
	else
		notify-send -t 1500 -h string:x-canonical-private-synchronous:volume -h int:value:"$vol_level" "Volume ${vol_level}%"
	fi
}

manage_volume "$1"
