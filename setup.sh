#!/bin/bash

set -Ee

_on_error() {
    local exit_code=$?
    local failed_cmd="$BASH_COMMAND"
    trap - ERR
    set +e

    printf '\n\033[1;31m[✗] Échec (code %d) : %s\033[0m\n' "$exit_code" "$failed_cmd" >&2
    local i
    for ((i = 0; i < ${#FUNCNAME[@]} - 1; i++)); do
        printf '    à %s() — %s:%s\n' \
            "${FUNCNAME[i+1]}" \
            "${BASH_SOURCE[i+1]#"$SETUP_DIR"/}" \
            "${BASH_LINENO[i]}" >&2
    done
    exit "$exit_code"
}
trap _on_error ERR

export SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SETUP_DIR/profiles"

# --- CONFIGURATION GLOBALE ---
# Default answer when the setup asks for the wallpapers repository
export CFG_WALLPAPERS_REPO="https://github.com/kayzzel/wallpapers"

# Block patterns of the chosen profile (its variants go in PROFILE_CHOICES)
PROFILE_BLOCKS=()

# Prints the help message and exits.
_show_help() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Without -b or -m, asks for a profile, then for the blocks to run with the
profile's ones ticked. The blocks they need are added, and every block runs
after the ones it needs.

Options:
  -p, --profile <name>   Use this profile instead of asking for one
  -b, --block <pattern>  Run only the matching blocks and the ones they need,
                         without the menus (e.g. neovim, "app.*"); can be
                         repeated
  -m, --module <name>    Same for the blocks of modules/<name>.sh; can be
                         repeated
  -r, --resume <block>   Skip the blocks that run before this one
  -l, --list             List the blocks and the profiles
  -h, --help             Show this help message

Examples:
  ./setup.sh -p desktop
  ./setup.sh -m wallpapers
  ./setup.sh -b neovim -b "app.*"
  ./setup.sh -p full --resume shell
EOF
    exit 0
}

# Sources the core, then every module, which declares its blocks.
_load_modules() {
    source "$SETUP_DIR/modules/core.sh"

    local module
    for module in "$SETUP_DIR"/modules/*.sh; do
        if [ "$(basename "$module")" != "core.sh" ]; then
            source "$module"
        fi
    done
}

# Stops when a block needs or follows a block that does not exist (a typo in
# a module).
_check_blocks() {
    local id other
    for id in "${BLOCK_IDS[@]}"; do
        for other in ${BLOCK_NEEDS[$id]} ${BLOCK_AFTER[$id]}; do
            if [ -z "${BLOCK_FUNCTION[$other]}" ]; then
                log_error "Block $id refers to an unknown block: $other"
                exit 1
            fi
        done
    done
}

# Prints the ids of the blocks matching shell patterns (e.g. "app.*").
#
# Args:
#   ...: The patterns.
_matching_blocks() {
    local id pattern
    for id in "${BLOCK_IDS[@]}"; do
        for pattern in "$@"; do
            if [[ "$id" == $pattern ]]; then
                echo "$id"
                break
            fi
        done
    done
}

# Prints the ids of the blocks declared by a module.
#
# Args:
#   name: The module name (modules/<name>.sh).
_module_blocks() {
    local id
    for id in "${BLOCK_IDS[@]}"; do
        if [ "${BLOCK_SOURCE[$id]}" = "$SETUP_DIR/modules/$1.sh" ]; then
            echo "$id"
        fi
    done
}

# Reads a profile: its block patterns into PROFILE_BLOCKS and its variants
# into PROFILE_CHOICES. Warns about the patterns matching no block and the
# variants of folders that are not choices.
#
# Args:
#   name: The profile name (profiles/<name>.profile).
_load_profile() {
    local name="$1"
    local file="$PROFILES_DIR/$name.profile"
    if [ ! -f "$file" ]; then
        log_error "Unknown profile: $name (see ./setup.sh --list)"
        exit 1
    fi

    local keyword arg value
    while read -r keyword arg value; do
        case "$keyword" in
            "" | "#"*) ;;
            block)
                PROFILE_BLOCKS+=("$arg")
                if [ -z "$(_matching_blocks "$arg")" ]; then
                    log_warn "$name.profile: no block matches $arg"
                fi
                ;;
            choice)
                PROFILE_CHOICES[$arg]="$value"
                if [ ! -f "$SETUP_DIR/$arg/.choice" ]; then
                    log_warn "$name.profile: $arg is not a choice folder"
                fi
                ;;
            *) log_warn "$name.profile: unknown line: $keyword $arg $value" ;;
        esac
    done < "$file"
}

# Returns success when the profile ticks a block.
#
# Args:
#   id: The block id.
_in_profile() {
    local pattern
    for pattern in "${PROFILE_BLOCKS[@]}"; do
        if [[ "$1" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# Returns success when a block is offered in the menu: it applies to this
# machine, is not required, and is not a component its element needs.
#
# Args:
#   id: The block id.
_offered() {
    local id="$1"
    if [ -n "${BLOCK_REQUIRED[$id]}" ] || ! block_available "$id"; then
        return 1
    fi

    local element="${id%%.*}"
    if [ "$element" != "$id" ] && [[ " ${BLOCK_NEEDS[$element]} " == *" $id "* ]]; then
        return 1
    fi
}

# Prints a block id, indented when it is a component of a declared element.
#
# Args:
#   id: The block id.
_block_label() {
    local element="${1%%.*}"
    if [ "$element" != "$1" ] && [ -n "${BLOCK_FUNCTION[$element]}" ]; then
        echo "  $1"
    else
        echo "$1"
    fi
}

# Prints the menu preview of a block: its description, the comment above its
# function and its dependencies.
#
# Args:
#   id: The block id.
_block_preview() {
    local id="$1"
    printf '%s\n%s\n\n' "$id" "${BLOCK_DESCRIPTION[$id]}"
    block_doc "$id"
    if [ -n "${BLOCK_NEEDS[$id]}" ]; then
        printf '\nNeeds (added automatically): %s\n' "${BLOCK_NEEDS[$id]% }"
    fi
    if [ -n "${BLOCK_AFTER[$id]}" ]; then
        printf '\nRuns after, when selected: %s\n' "${BLOCK_AFTER[$id]% }"
    fi
}

# Installs fzf, which shows the menus, when it is missing.
_ensure_fzf() {
    if ! command -v fzf > /dev/null; then
        log_info "Installing fzf for the setup menus..."
        sudo pacman -S --needed --noconfirm fzf
    fi
}

# Asks which profile to start from and prints its name ("none" ticks
# nothing). Prints nothing when cancelled (Esc).
_choose_profile() {
    local file name
    {
        printf 'none\t%-12s %s\n' "none" "Nothing ticked, variants asked"
        for file in "$PROFILES_DIR"/*.profile; do
            name=$(basename "$file" .profile)
            printf '%s\t%-12s %s\n' "$name" "$name" "$(sed -n '1s/^# *//p' "$file")"
        done
    } | fzf --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Profile " --prompt "Profile > " \
            --header "Enter: choose  Esc: quit" \
            --preview "cat '$PROFILES_DIR'/{1}.profile 2>/dev/null || echo 'Nothing ticked, the variants are asked.'" \
            --preview-window "right,55%,wrap" \
        | cut -f 1
}

# Asks which blocks to run, with the ones of the profile ticked, and prints
# their ids (none when nothing is ticked). Returns 1 when cancelled (Esc).
#
# Args:
#   profile: The profile name, shown in the menu.
_choose_blocks() {
    local profile="$1"
    local previews
    previews=$(mktemp -d)

    local lines=() ticks="" position=0 id
    for id in "${BLOCK_IDS[@]}"; do
        if ! _offered "$id"; then
            continue
        fi
        position=$((position + 1))
        lines+=("$(printf '%s\t%-28s %s' "$id" "$(_block_label "$id")" "${BLOCK_DESCRIPTION[$id]}")")
        _block_preview "$id" > "$previews/$id"

        # Ticks the line once fzf has read the list
        if _in_profile "$id"; then
            ticks+="pos($position)+select+"
        fi
    done

    # Enter with nothing ticked prints nothing instead of the current line
    local selection status=0
    selection=$(printf '%s\n' "${lines[@]}" | fzf --multi \
            --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Blocks — profile: $profile " \
            --prompt "Blocks > " \
            --header "Tab: tick/untick  Enter: run the ticked blocks  Esc: quit" \
            --preview "cat '$previews'/{1}" --preview-window "right,45%,wrap" \
            --bind "load:${ticks}first" \
            --bind 'enter:transform:if [ "$FZF_SELECT_COUNT" -eq 0 ]; then echo "become(true)"; else echo accept; fi') \
        || status=$?
    rm -rf "$previews"

    if [ "$status" -ne 0 ]; then
        return 1
    fi
    if [ -n "$selection" ]; then
        cut -f 1 <<< "$selection"
    fi
}

# Adds to the selection the blocks the selected ones need, recursively, when
# they apply to this machine, and tells which ones were added.
#
# Args:
#   selection: The name of an associative array (block id -> 1).
_add_needed_blocks() {
    local -n wanted="$1"
    local added=1 id need
    while [ "$added" -eq 1 ]; do
        added=0
        for id in "${!wanted[@]}"; do
            for need in ${BLOCK_NEEDS[$id]}; do
                if [ -z "${wanted[$need]}" ] && block_available "$need"; then
                    wanted[$need]=1
                    added=1
                    log_info "Adding $need (needed by $id)"
                fi
            done
        done
    done
}

# Puts the selected blocks in run order: the required ones first, then each
# block after the selected blocks it needs or follows, in declaration order
# otherwise. Stops on a dependency cycle.
#
# Args:
#   selection: The name of an associative array (block id -> 1).
#   order: The name of the array receiving the ordered ids.
_run_order() {
    local -n wanted="$1"
    local -n ordered="$2"
    local -A placed=()
    local group id other ready next pending

    for group in required others; do
        while true; do
            next=""
            pending=()
            for id in "${BLOCK_IDS[@]}"; do
                if [ -z "${wanted[$id]}" ] || [ -n "${placed[$id]}" ]; then
                    continue
                fi
                if [ "$group" = required ] && [ -z "${BLOCK_REQUIRED[$id]}" ]; then
                    continue
                fi
                pending+=("$id")

                ready=1
                for other in ${BLOCK_NEEDS[$id]} ${BLOCK_AFTER[$id]}; do
                    if [ -n "${wanted[$other]}" ] && [ -z "${placed[$other]}" ]; then
                        ready=0
                        break
                    fi
                done
                if [ "$ready" -eq 1 ]; then
                    next="$id"
                    break
                fi
            done

            if [ -n "$next" ]; then
                ordered+=("$next")
                placed[$next]=1
            elif [ "${#pending[@]}" -gt 0 ]; then
                log_error "Dependency cycle between: ${pending[*]}"
                exit 1
            else
                break
            fi
        done
    done
}

# Prints the blocks, with how they are offered on this machine, and the
# profiles.
_list() {
    local id state file
    printf '\nBlocks (id, module, description):\n\n'
    for id in "${BLOCK_IDS[@]}"; do
        state=""
        if ! block_available "$id"; then
            state="not for this machine"
        elif [ -n "${BLOCK_REQUIRED[$id]}" ]; then
            state="always run"
        elif ! _offered "$id"; then
            state="installed with ${id%%.*}"
        fi

        printf '  %-28s %-15s %s' "$(_block_label "$id")" \
            "$(basename "${BLOCK_SOURCE[$id]}" .sh)" "${BLOCK_DESCRIPTION[$id]}"
        if [ -n "$state" ]; then
            printf ' \033[2m(%s)\033[0m' "$state"
        fi
        printf '\n'
    done

    printf '\nProfiles (./setup.sh -p <name>):\n\n'
    for file in "$PROFILES_DIR"/*.profile; do
        printf '  %-12s %s\n' "$(basename "$file" .profile)" "$(sed -n '1s/^# *//p' "$file")"
    done
    printf '\n'
}

# Main orchestration function for the setup process.
#
# Args:
#   @: Command line arguments.
main() {
    local profile="" resume="" list=false
    local patterns=() modules=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -p|--profile) profile="$2"; shift 2 ;;
            -b|--block) patterns+=("$2"); shift 2 ;;
            -m|--module) modules+=("$2"); shift 2 ;;
            -r|--resume) resume="$2"; shift 2 ;;
            -l|--list) list=true; shift ;;
            -h|--help) _show_help ;;
            *) echo "Unknown parameter: $1"; exit 1 ;;
        esac
    done

    _load_modules
    _check_blocks

    if [ "$list" = true ]; then
        _list
        exit 0
    fi

    if [ -n "$profile" ]; then
        _load_profile "$profile"
    fi

    local -A selection=()
    local id

    if [ "${#patterns[@]}" -gt 0 ] || [ "${#modules[@]}" -gt 0 ]; then
        # Direct mode: the given blocks, without the menus nor the required ones
        local pattern module
        for pattern in "${patterns[@]}"; do
            if [ -z "$(_matching_blocks "$pattern")" ]; then
                log_warn "No block matches $pattern (see ./setup.sh --list)"
            fi
        done
        for module in "${modules[@]}"; do
            if [ ! -f "$SETUP_DIR/modules/$module.sh" ]; then
                log_warn "No module named $module (see modules/)"
            fi
        done

        for id in $(_matching_blocks "${patterns[@]}") $(for module in "${modules[@]}"; do _module_blocks "$module"; done); do
            if block_available "$id"; then
                selection[$id]=1
            else
                log_warn "Skipping $id: not for this machine"
            fi
        done
    else
        _ensure_fzf

        if [ -z "$profile" ]; then
            profile=$(_choose_profile)
            if [ -z "$profile" ]; then
                log_info "Setup cancelled."
                exit 0
            fi
            if [ "$profile" != "none" ]; then
                _load_profile "$profile"
            fi
        fi

        local chosen
        if ! chosen=$(_choose_blocks "$profile"); then
            log_info "Setup cancelled."
            exit 0
        fi

        for id in $chosen; do
            selection[$id]=1
        done
        for id in "${BLOCK_IDS[@]}"; do
            if [ -n "${BLOCK_REQUIRED[$id]}" ] && block_available "$id"; then
                selection[$id]=1
            fi
        done
    fi

    init_ui

    _add_needed_blocks selection

    local order=()
    _run_order selection order

    if [ -n "$resume" ]; then
        local index
        for index in "${!order[@]}"; do
            if [ "${order[index]}" = "$resume" ]; then
                order=("${order[@]:index}")
                break
            fi
        done
        if [ "${order[0]}" != "$resume" ]; then
            log_error "Cannot resume from $resume: it is not part of this run."
            exit 1
        fi
    fi

    if [ "${#order[@]}" -eq 0 ]; then
        log_warn "No block to run."
        exit 0
    fi

    log_info "Running ${#order[@]} blocks: ${order[*]}"
    printf "\n"

    for id in "${order[@]}"; do
        run_block "$id"
    done

    sleep 0.5
    log_success "Setup completed successfully! Please reboot."
}

main "$@"
