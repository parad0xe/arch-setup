#!/bin/bash

killall mpvpaper
mpvpaper -o "loop no-audio" "*" "$1" & disown
