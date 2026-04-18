#!/bin/bash

clipboard_notification() {
    local timeout="$1"
    local title="$2"
    local flag="/tmp/clipinit"

    rm -f "$flag"

    wl-paste --watch bash -c "
        if [ -f $flag ]; then
            notify-send -t $timeout '$title' 'Content copied to clipboard'
        else
            touch $flag
        fi
    "
}

clipboard_notification 2000 "Clipboard"
