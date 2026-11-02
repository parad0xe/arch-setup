#!/bin/bash

# Monitor clipboard events and trigger a synchronized notification.
manage_clipboard() {
	local flag="/tmp/clipinit"

	# Remove the startup flag to prevent a notification on launch.
	rm -f "$flag"

	# Start the Wayland clipboard watcher in a continuous loop.
	wl-paste --watch bash -c '
		if [ -f /tmp/clipinit ]; then
			notify-send -c clipboard -h string:x-canonical-private-synchronous:clipboard "Clipboard" "Content copied"
		else
			# Create the flag after the initial silent trigger.
			touch /tmp/clipinit
		fi
	'
}

manage_clipboard
