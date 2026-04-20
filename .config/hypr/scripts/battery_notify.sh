#!/bin/bash

# Play a system alert sound without blocking the script execution.
# sound_name: name of the freedesktop sound file without extension
play_alert() {
	local sound_name="$1"
	local path="/usr/share/sounds/freedesktop/stereo"
	
	# Vérifie que paplay existe et que le son est présent
	if command -v paplay &>/dev/null && [ -f "$path/$sound_name.oga" ]; then
		paplay "$path/$sound_name.oga" &
	fi
}

# Monitor battery level and send notifications on low capacity.
# warning: percentage threshold for standard low battery warning
# critical: percentage threshold for critical battery warning
monitor_battery() {
	local warning="$1"
	local critical="$2"
	local bat_path="/sys/class/power_supply/BAT0"
	
	local lock_warning=false
	local lock_critical=false

	while true; do
		if [ -d "$bat_path" ]; then
			local capacity=$(cat "$bat_path/capacity")
			local status=$(cat "$bat_path/status")

			if [ "$status" = "Discharging" ]; then
				if [ "$capacity" -le "$critical" ] && [ "$lock_critical" = false ]; then
					play_alert "dialog-error"
					notify-send -u critical "Battery Critical" "Level at ${capacity}%!"
					lock_critical=true
					lock_warning=true
				elif [ "$capacity" -le "$warning" ] && [ "$capacity" -gt "$critical" ] && [ "$lock_warning" = false ]; then
					play_alert "dialog-warning"
					notify-send -u normal "Battery Low" "Level at ${capacity}%."
					lock_warning=true
				fi
			elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
				lock_warning=false
				lock_critical=false
			fi
		fi
		sleep 60
	done
}

monitor_battery 20 10
