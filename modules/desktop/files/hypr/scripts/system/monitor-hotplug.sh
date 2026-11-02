#!/bin/bash

# Continuously listen to the Hyprland event socket
socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    
    # If the event is a monitor being added
    if [[ "$line" == "monitoradded>>"* ]]; then
        # One-second pause to let Hyprland initialize the resolution
        sleep 1
        
        # Launch the _restore_desktop function to apply the wallpaper on the new screen
        ~/.config/hypr/scripts/change-wall.sh
    fi

done
