#!/bin/bash

# A choice is a folder holding a .choice file (its description on the first
# line) and one file per variant. The selected variant is linked as
# selected.<ext> in the same folder, and the configs include that link.

# Removes the selection link(s) of a choice folder.
#
# Args:
#   dir: The choice folder.
_clear_selection() {
    local link
    for link in "$1"/selected "$1"/selected.*; do
        if [ -L "$link" ]; then
            rm "$link"
        fi
    done
}

# Asks which variant of a choice to use and links it as selected.<ext>.
#
# Args:
#   dir: The choice folder.
_choose_variant() {
    local dir="$1"
    local description
    description=$(head -n 1 "$dir/.choice")

    local variants=()
    local file
    for file in "$dir"/*; do
        if [ -f "$file" ] && [ ! -L "$file" ]; then
            variants+=("$(basename "$file")")
        fi
    done

    if [ "${#variants[@]}" -eq 0 ]; then
        log_warn "No variant found for: $description"
        return 0
    fi

    local current="${variants[0]}"
    local variant
    for variant in "${variants[@]}"; do
        if [ "${variant%.*}" = "default" ]; then
            current="$variant"
        fi
    done

    local link
    for link in "$dir"/selected "$dir"/selected.*; do
        if [ -L "$link" ] && [ -e "$link" ]; then
            current=$(basename "$(readlink "$link")")
        fi
    done

    log_info "$description (${dir#"$SETUP_DIR"/}):"
    local i
    for i in "${!variants[@]}"; do
        local mark=""
        if [ "${variants[i]}" = "$current" ]; then
            mark=" (current)"
        fi
        printf "      %d) %s%s\n" "$((i + 1))" "${variants[i]%.*}" "$mark" > /dev/tty
    done

    local answer=""
    while true; do
        printf "\r\033[K\033[1;34m[i]\033[0m Which one? [Enter = %s]: " "${current%.*}" > /dev/tty
        read -r answer < /dev/tty

        if [ -z "$answer" ]; then
            answer="$current"
            break
        fi

        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#variants[@]} )); then
            answer="${variants[answer - 1]}"
            break
        fi

        log_warn "Invalid choice: $answer"
    done

    local name="selected"
    if [[ "$answer" == *.* ]]; then
        name="selected.${answer##*.}"
    fi

    _clear_selection "$dir"
    ln -s "$answer" "$dir/$name"
    log_success "$description: ${answer%.*}"
}

# Entry point for the choices module.
setup() {
    local marker
    while IFS= read -r marker; do
        _choose_variant "$(dirname "$marker")"
    done < <(find "$SETUP_DIR" -name .choice -not -path "*/.git/*" | sort)
}
