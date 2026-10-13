#!/bin/bash
# Always re-enable the internal laptop keyboard before locking, so it's
# never possible to get locked out with no way to type your password.
#
~/.config/hypr/scripts/toggle-laptop-kb.sh enable
hyprlock
