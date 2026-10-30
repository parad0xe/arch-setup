#!/bin/bash

# Adjust system volume via WirePlumber and send a synchronized notification.
# action: the operation to perform ("up", "down", or "mute")
manage_volume() {
	local action="$1"
	
	# Execute the corresponding WirePlumber command based on user input.
	case "$action" in
		up)
			# Increase volume by 5%, capped at 100% maximum.
			wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
			;;
		down)
			# Decrease volume by 5%.
			wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
			;;
		mute)
			# Toggle the mute state of the default audio sink.
			wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
			;;
	esac

	# Fetch the current volume level status.
	local vol_status=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
	
	# Convert float value to an integer percentage.
	local vol_level=$(echo "$vol_status" | awk '{printf "%.0f\n", $2 * 100}')

	# Check if the volume is currently muted.
	if echo "$vol_status" | grep -q "MUTED"; then
		# Send a synchronized notification for the muted state.
		notify-send -t 1500 -h string:x-canonical-private-synchronous:volume "Volume muted"
	else
		# Send a synchronized notification with the volume progress bar.
		notify-send -t 1500 -h string:x-canonical-private-synchronous:volume -h int:value:"$vol_level" "Volume ${vol_level}%"
	fi
}

manage_volume "$1"
