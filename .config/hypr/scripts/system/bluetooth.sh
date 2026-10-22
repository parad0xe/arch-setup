#!/bin/bash

# Opens bluetui, the Bluetooth manager, in a floating Ghostty window (see
# conf/windowrules.lua). bluetui stops when the Bluetooth radio is soft
# blocked (rfkill): it is unblocked first, which the user of the session may
# do without sudo, then the adapter is waited for in BlueZ.

if rfkill list bluetooth | grep -q 'Hard blocked: yes'; then
    notify-send -u critical "Bluetooth" "The Bluetooth radio is turned off by a hardware switch."
    exit 1
fi

if rfkill list bluetooth | grep -q 'Soft blocked: yes'; then
    rfkill unblock bluetooth
    # Up to 2 seconds for the adapter to show up
    for _ in {1..20}; do
        bluetoothctl list | grep -q '^Controller' && break
        sleep 0.1
    done
fi

exec ghostty --class=ghostty.bluetui -e bluetui
