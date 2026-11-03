#!/bin/bash

# Opens rmpc, the MPD client, in a floating Ghostty window (see
# conf/windowrules.lua). MPD itself runs as a systemd user service,
# enabled by the mpd unit (modules/extra); this script only starts the
# client.

exec ghostty --class=ghostty.rmpc -e rmpc
