#!/bin/bash

# Opens rmpc, the MPD client, in a floating Ghostty window (see
# conf/windowrules.lua). MPD itself is started as a systemd user
# service by conf/autostart/kayzzel.lua; this script only starts the
# client.

exec ghostty --class=ghostty.rmpc -e rmpc
