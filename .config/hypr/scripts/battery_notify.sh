#!/bin/bash

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
					notify-send -u critical "Battery Critical" "Level at ${capacity}%!"
					lock_critical=true
					lock_warning=true
				elif [ "$capacity" -le "$warning" ] && [ "$capacity" -gt "$critical" ] && [ "$lock_warning" = false ]; then
					notify-send -u normal "Battery Low" "Level at ${capacity}%."
					lock_warning=true
				fi
			elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
				# Reset locks when plugged in
				lock_warning=false
				lock_critical=false
			fi
		fi
		# Check every 60 seconds
		sleep 60
	done
}

# Start monitoring with Warning at 20% and Critical at 10%
monitor_battery 20 10
