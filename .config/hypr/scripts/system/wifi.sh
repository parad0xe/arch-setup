#!/bin/bash

# Opens wlctl, the Wi-Fi manager (NetworkManager), in a floating Ghostty
# window (see conf/windowrules.lua). A soft blocked radio is left as is:
# wlctl shows the Wi-Fi off and turns it on (o). A hardware switch cannot be
# turned on from there, so it is only reported.

if rfkill list wlan | grep -q 'Hard blocked: yes'; then
    notify-send -u critical "Wi-Fi" "The Wi-Fi radio is turned off by a hardware switch."
    exit 1
fi

exec ghostty --class=ghostty.wlctl -e wlctl
