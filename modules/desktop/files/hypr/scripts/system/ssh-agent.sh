#!/usr/bin/env bash

export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

if ! pgrep -u "$USER" ssh-agent > /dev/null; then
  ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null
fi
