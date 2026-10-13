#!/bin/bash
# Toggles the internal laptop keyboard on/off, driven by a Waybar module.
# The keyboard is detected at each run, so nothing is machine-specific.

STATE_FILE="$XDG_RUNTIME_DIR/laptop-kb-disabled"

# Prints the Hyprland name of the internal keyboard: the one plugged into the
# i8042 controller, as on most laptops. Returns 1 if there is none.
_detect_keyboard() {
    local name
    name=$(awk 'BEGIN { RS = ""; FS = "\n" }
        /\/i8042\// && /Handlers=[^\n]*kbd/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^N: Name=/) {
                    sub(/^N: Name="/, "", $i)
                    sub(/"$/, "", $i)
                    print $i
                    exit
                }
            }
        }' /proc/bus/input/devices)
    [ -n "$name" ] || return 1

    name=$(echo "$name" | tr '[:upper:] ' '[:lower:]-')
    hyprctl devices -j | grep -qF "\"name\": \"$name\"" || return 1

    echo "$name"
}

# Enables or disables a keyboard right away.
#
# Args:
#   name: The Hyprland device name.
#   enabled: true or false.
_set_keyboard() {
    hyprctl eval "hl.device({ name = \"$1\", enabled = $2 })" > /dev/null
}

# Tells Waybar to re-run this module's exec immediately instead of
# waiting for the next interval (paired with "signal": 8 in its config).
_refresh_waybar() {
    pkill -RTMIN+8 waybar 2>/dev/null
}

status() {
    if ! _detect_keyboard > /dev/null; then
        echo '{"text": "⌨", "tooltip": "Laptop keyboard: not detected", "class": "unavailable"}'
    elif [ -f "$STATE_FILE" ]; then
        echo '{"text": "⌨", "tooltip": "Laptop keyboard: disabled — click to enable", "class": "disabled"}'
    else
        echo '{"text": "⌨", "tooltip": "Laptop keyboard: enabled — click to disable", "class": "enabled"}'
    fi
}

toggle() {
    local kb
    if ! kb=$(_detect_keyboard); then
        notify-send -t 3000 "Laptop Keyboard" "No internal keyboard detected"
        return 1
    fi

    if [ -f "$STATE_FILE" ]; then
        _set_keyboard "$kb" true
        rm -f "$STATE_FILE"
        notify-send -t 1500 "Laptop Keyboard" "Enabled"
    else
        _set_keyboard "$kb" false
        touch "$STATE_FILE"
        notify-send -t 1500 "Laptop Keyboard" "Disabled"
    fi
    _refresh_waybar
}

# Forces the keyboard back on with no toggle logic and no notification —
# used by lock.sh so you can always type your password to unlock.
enable() {
    local kb
    if kb=$(_detect_keyboard); then
        _set_keyboard "$kb" true
    fi
    rm -f "$STATE_FILE"
    _refresh_waybar
}

case "$1" in
    toggle) toggle ;;
    enable) enable ;;
    *) status ;;
esac
