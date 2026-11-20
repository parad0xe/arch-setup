#!/bin/bash

# Opens eqtui, the TUI equalizer (editable bands with a live response graph,
# profiles, device picker), in a floating Ghostty window (see
# conf/windowrules.lua), like the Wi-Fi, Bluetooth and sound managers. The
# EQ engine runs as a background daemon (conf/autostart.lua: eqtui daemon),
# so the equalizer keeps applying after the window is closed; q only
# detaches the TUI, `eqtui attach` reopens it.

# eqtui is built by cargo into ~/.cargo/bin; a Hyprland session started from
# SDDM does not source the shell rc files, so fall back to the absolute path.
EQTUI=$(command -v eqtui 2> /dev/null || true)
if [ -z "$EQTUI" ] && [ -x "$HOME/.cargo/bin/eqtui" ]; then
    EQTUI="$HOME/.cargo/bin/eqtui"
fi
if [ -z "$EQTUI" ]; then
    notify-send -u critical "EQ" "eqtui is not installed; run the setup (sound-manager unit)."
    exit 1
fi

exec ghostty --class=ghostty.eqtui -e "$EQTUI"
