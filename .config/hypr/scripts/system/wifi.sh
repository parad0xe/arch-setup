#!/bin/bash

# Display a Rofi menu to scan, select, and connect to Wi-Fi networks.
manage_wifi() {
	local scan_id
	# Trigger the scanning notification and store its ID.
	scan_id=$(notify-send -p -c wifi-scan "Wi-Fi" "Scanning...")
	
	local list
	# Fetch, sort, and format the list of available Wi-Fi networks.
	list=$(nmcli -t -f SSID,SIGNAL device wifi list | grep -v "^:" | \
		sort -t: -k2 -nr | awk -F: '!seen[$1]++ {print $1 " (" $2 "%)"}')
	
	# Dismiss the scanning notification once the list is ready.
	makoctl dismiss -n "$scan_id" 2>/dev/null
	
	local choice
	# Open the Rofi selection menu.
	choice=$(echo "$list" | rofi -dmenu -i -p "󰤨" -theme ~/.config/rofi/wifi.rasi)
	
	[ -z "$choice" ] && return
	
	local ssid
	# Extract the pure SSID from the selected line.
	ssid=$(echo "$choice" | sed 's/ (.*)//')
	
	# Check if the network profile is already known by NetworkManager.
	if nmcli -t -f NAME connection show | grep -Fxq "$ssid"; then
		local conn_id
		# Trigger the switching notification.
		conn_id=$(notify-send -p -c wifi-auth "Wi-Fi" "Switching...")
		
		# Attempt to connect to the known network.
		if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
			makoctl dismiss -n "$conn_id" 2>/dev/null
			notify-send -c wifi-result -u normal "Wi-Fi" "Successfully connected to $ssid"
		else
			makoctl dismiss -n "$conn_id" 2>/dev/null
			notify-send -c wifi-result -u critical "Wi-Fi" "Connection to $ssid failed"
		fi
	else
		local pass
		# Prompt the user for the new network password securely.
		pass=$(rofi -dmenu -password -p "󰌾 $ssid" -theme ~/.config/rofi/wifi-pass.rasi < /dev/null)
		
		[ -z "$pass" ] && return
		
		local auth_id
		# Trigger the authentication notification.
		auth_id=$(notify-send -p -c wifi-auth "Wi-Fi" "Authenticating...")
		
		# Attempt to authenticate and connect to the new network.
		if nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1; then
			makoctl dismiss -n "$auth_id" 2>/dev/null
			notify-send -c wifi-result -u normal "Wi-Fi" "Successfully connected to $ssid"
		else
			makoctl dismiss -n "$auth_id" 2>/dev/null
			notify-send -c wifi-result -u critical "Wi-Fi" "Authentication for $ssid failed"
		fi
	fi
}

manage_wifi
