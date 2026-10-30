#!/bin/bash

# Play a system alert sound without blocking the script execution.
# sound_name: name of the sound file to be played
play_alert() {
	local sound_name="$1"
	local path="/usr/share/sounds/freedesktop/stereo"
	
	# Check if the audio player and the sound file exist.
	if command -v paplay &>/dev/null && [ -f "$path/$sound_name.oga" ]; then
		# Run audio playback in the background.
		paplay "$path/$sound_name.oga" &
	fi
}

# Monitor battery level and send notifications on low capacity.
# warning: battery level threshold for the first alert
# critical: battery level threshold for the final alert
monitor_battery() {
	local warning="$1"
	local critical="$2"
	local bat_path="/sys/class/power_supply/BAT0"
	
	local lock_warning=false
	local lock_critical=false
	# Store the previous capacity to detect percentage drops.
	local last_capacity=$(cat "$bat_path/capacity")

	while true; do
		if [ -d "$bat_path" ]; then
			local capacity=$(cat "$bat_path/capacity")
			local status=$(cat "$bat_path/status")

			if [ "$status" = "Discharging" ]; then
				# Trigger critical alert if below threshold and unlocked.
				if [ "$capacity" -le "$critical" ] && [ "$lock_critical" = false ]; then
					play_alert "dialog-error"
					notify-send -c battery-critical -u critical -h string:x-canonical-private-synchronous:battery "Battery Low" "Level: ${capacity}%"
					lock_critical=true
					lock_warning=true
				# Trigger warning alert if below threshold and unlocked.
				elif [ "$capacity" -le "$warning" ] && [ "$capacity" -gt "$critical" ] && [ "$lock_warning" = false ]; then
					play_alert "dialog-warning"
					notify-send -c battery-warning -u normal -h string:x-canonical-private-synchronous:battery "Battery Warning" "Level: ${capacity}%"
					lock_warning=true
				fi

				# Play an alert for every percentage drop below the 5% floor.
				if [ "$capacity" -le 5 ] && [ "$capacity" -lt "$last_capacity" ]; then
					play_alert "message-new-instant"
					notify-send -c battery-critical -u critical -h string:x-canonical-private-synchronous:battery "Battery Critical" "Level: ${capacity}%"
				fi
			elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
				# Reset notification locks when the device is plugged in.
				lock_warning=false
				lock_critical=false
			fi
			# Update the tracking variable for the next iteration.
			last_capacity=$capacity
		fi
		# Wait for 60 seconds before checking the battery again.
		sleep 60
	done
}

# Start monitoring with Warning at 20 percent and Critical at 10 percent.
monitor_battery 20 10
