#!/usr/bin/env bash
set -euo pipefail

declare -a labels=()
declare -a backends=()
declare -a targets=()

# External monitors via ddcutil (skips laptop panels automatically,
# since they show as "Invalid display" rather than "Display N")
if command -v ddcutil &>/dev/null; then
    current_display=""
    while IFS= read -r line; do
        if [[ $line =~ ^Display\ ([0-9]+)$ ]]; then
            current_display="${BASH_REMATCH[1]}"
        elif [[ -n "$current_display" && $line =~ Model:\ *(.+)$ ]]; then
            labels+=("${BASH_REMATCH[1]} (Display $current_display)")
            backends+=("ddcutil")
            targets+=("$current_display")
            current_display=""
        fi
    done < <(ddcutil detect 2>/dev/null)
fi

# Laptop panel via brightnessctl
if command -v brightnessctl &>/dev/null; then
    while IFS= read -r line; do
        if [[ $line =~ Device\ \'([^\']+)\'\ of\ class\ \'([^\']+)\' ]]; then
            dev="${BASH_REMATCH[1]}"
            class="${BASH_REMATCH[2]}"
            if [[ "$class" == "backlight" ]]; then
                labels+=("Laptop panel ($dev)")
                backends+=("brightnessctl")
                targets+=("$dev")
            fi
        fi
    done < <(brightnessctl -l 2>/dev/null)
fi

if [[ ${#labels[@]} -eq 0 ]]; then
    notify-send "Brightness" "No controllable displays found"
    exit 1
fi

selected=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -p "Select monitor")
[[ -z "$selected" ]] && exit 0

index=-1
for i in "${!labels[@]}"; do
    [[ "${labels[$i]}" == "$selected" ]] && index=$i && break
done
[[ $index -eq -1 ]] && exit 1

backend="${backends[$index]}"
target="${targets[$index]}"

level=$(printf '%s\n' 0 10 20 30 40 50 60 70 80 90 100 | rofi -dmenu -p "Brightness %")
[[ -z "$level" || ! "$level" =~ ^[0-9]+$ ]] && exit 0

case "$backend" in
    ddcutil) ddcutil setvcp 10 "$level" -d "$target" ;;
    brightnessctl) brightnessctl -d "$target" set "${level}%" ;;
esac

notify-send "Brightness" "$selected set to ${level}%"
