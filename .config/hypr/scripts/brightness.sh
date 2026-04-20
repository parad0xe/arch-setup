#!/bin/bash

# Adjust screen brightness and send a synchronized notification.
# action: the operation to perform ("up" or "down")
manage_brightness() {
	local action="$1"
	
	# brightnessctl -m: intel_backlight,backlight,120,50%,240
	local b_level
	b_level=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')

	case "$action" in
		up)
			brightnessctl set 5%+ > /dev/null
			;;
		down)
			if [ "$b_level" -gt 5 ]; then
				brightnessctl set 5%- > /dev/null
			else
				brightnessctl set 5% > /dev/null
			fi
			;;
	esac

	b_level=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')
	notify-send -c brightness -t 1500 -h string:x-canonical-private-synchronous:brightness -h int:value:"$b_level" "Brightness ${b_level}%"
}

manage_brightness "$1"
