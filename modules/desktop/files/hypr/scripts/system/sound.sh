#!/bin/bash

# Opens wiremix, the TUI sound manager (volumes, per-application streams,
# output/input device routing), in a floating Ghostty window (see
# conf/windowrules.lua), like the Wi-Fi and Bluetooth managers. The
# equalizer is a PipeWire smart filter attached to the default output
# (SUPER + SHIFT + V switches presets, scripts/system/eq.sh).

exec ghostty --class=ghostty.wiremix -e wiremix
