#!/bin/bash

# Adjust screen brightness and send a synchronized notification.
# action: the operation to perform ("up" or "down")
manage_brightness() {
	local action="$1"
	
	# Extract the current brightness percentage from the system.
	local b_level
	b_level=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')

	# Execute the brightness command based on the requested action.
	case "$action" in
		up)
			# Increase brightness by 5 percent.
			brightnessctl set 5%+ > /dev/null
			;;
		down)
			# Check if decreasing keeps brightness above the 5 percent threshold.
			if [ "$b_level" -gt 5 ]; then
				# Decrease brightness by 5 percent safely.
				brightnessctl set 5%- > /dev/null
			else
				# Lock brightness at 5 percent to prevent screen blackout.
				brightnessctl set 5% > /dev/null
			fi
			;;
	esac

	# Read the updated brightness level after the modification.
	b_level=$(brightnessctl -m | cut -d',' -f4 | tr -d '%')
	
	# Send a synchronized notification displaying the new brightness level.
	notify-send -c brightness -t 1500 -h string:x-canonical-private-synchronous:brightness -h int:value:"$b_level" "Brightness ${b_level}%"
}

manage_brightness "$1"
