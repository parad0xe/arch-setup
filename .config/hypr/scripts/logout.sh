#!/bin/bash
# Logs out with hyprshutdown, which asks the apps to close before quitting
# Hyprland. SDDM's X11 login screen does not take the screen back by itself
# after a Wayland session (black screen), so hyprshutdown then switches to
# the virtual terminal of SDDM's X server.
#

sddm_vt=$(pgrep -a Xorg | grep /run/sddm/ | grep -o ' vt[0-9]\+' | head -n 1)
sddm_vt="${sddm_vt# vt}"

if [ -n "$sddm_vt" ]; then
    hyprshutdown --vt "$sddm_vt"
else
    hyprshutdown
fi
