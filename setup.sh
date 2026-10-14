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
# Profiles saved from the summary, outside the repository. They take
# precedence over the repository's profiles of the same name.
USER_PROFILES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/arch-setup/profiles"

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
profile's ones selected, and shows what will run before installing it. The
blocks they need are added, and every block runs after the ones it needs.

Options:
  -p, --profile <name>   Use this profile instead of asking for one (from
                         ~/.local/share/arch-setup/profiles, where the menu
                         saves them, or else from profiles/)
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

# Prints the file of a profile: the local one (USER_PROFILES_DIR) when there
# is one, the repository's one otherwise. Returns 1 when there is none.
#
# Args:
#   name: The profile name.
_profile_file() {
    local dir
    for dir in "$USER_PROFILES_DIR" "$PROFILES_DIR"; do
        if [ -f "$dir/$1.profile" ]; then
            echo "$dir/$1.profile"
            return 0
        fi
    done
    return 1
}

# Prints the names of the profiles, local and from the repository, once
# each and sorted.
_profile_names() {
    local file
    for file in "$USER_PROFILES_DIR"/*.profile "$PROFILES_DIR"/*.profile; do
        if [ -f "$file" ]; then
            basename "$file" .profile
        fi
    done | sort -u
}

# Prints the description of a profile (the first line of its file, without
# its "#"), followed by "(local)" when it is a local one.
#
# Args:
#   name: The profile name.
_profile_description() {
    local file
    file=$(_profile_file "$1")
    printf '%s' "$(sed -n '1s/^# *//p' "$file")"
    if [ "$file" = "$USER_PROFILES_DIR/$1.profile" ]; then
        printf ' (local)'
    fi
    printf '\n'
}

# Reads a profile: its block patterns into PROFILE_BLOCKS and its variants
# into PROFILE_CHOICES. Warns about the patterns matching no block and the
# variants of folders that are not choices.
#
# Args:
#   name: The profile name.
_load_profile() {
    local name="$1"
    local file
    if ! file=$(_profile_file "$name"); then
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

# Returns success when the profile selects a block.
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

# Prints a count followed by a noun, plural when needed (1 block, 2 blocks).
#
# Args:
#   count: The number.
#   noun: The noun, singular.
_count() {
    if [ "$1" -eq 1 ]; then
        echo "1 $2"
    else
        echo "$1 ${2}s"
    fi
}

# Fills the module of each block (modules/<module>.sh) and the list of the
# modules, in load order.
#
# Args:
#   module_of: The name of an associative array receiving block id -> module.
#   modules: The name of an array receiving the module names.
_index_modules() {
    local -n indexed_module_of="$1"
    local -n indexed_modules="$2"
    local id module
    for id in "${BLOCK_IDS[@]}"; do
        module="${BLOCK_SOURCE[$id]##*/}"
        module="${module%.sh}"
        indexed_module_of[$id]="$module"
        if [[ " ${indexed_modules[*]} " != *" $module "* ]]; then
            indexed_modules+=("$module")
        fi
    done
}

# Returns success when a block is a component of a declared element.
#
# Args:
#   id: The block id.
_is_component() {
    local element="${1%%.*}"
    [ "$element" != "$1" ] && [ -n "${BLOCK_FUNCTION[$element]}" ]
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

# Asks which profile to start from and prints its name ("none" selects
# nothing). Prints nothing when cancelled (Esc).
_choose_profile() {
    local name

    # One "name<TAB>shown line<TAB>file" line per profile
    {
        printf 'none\t%-16s %s\t\n' "none" "Nothing selected, variants asked"
        for name in $(_profile_names); do
            printf '%s\t%-16s %s\t%s\n' "$name" "$name" \
                "$(_profile_description "$name")" "$(_profile_file "$name")"
        done
    } | fzf --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Profile " --prompt "Profile > " \
            --header "Enter: choose  Esc: quit" \
            --preview "cat {3} 2>/dev/null || echo 'Nothing selected, the variants are asked.'" \
            --preview-window "right,55%,wrap" \
        | cut -f 1
}

# Writes the scripts of the blocks menu into its working folder: render
# prints the menu lines with their checkboxes, toggle selects or unselects a
# block or a whole section, and tab does it for the line under the cursor,
# then moves the cursor to the next line. fzf runs them with the user's
# shell, so they are standalone sh scripts.
#
# Args:
#   menu: The working folder of the menu (lines, selected, previews/).
_write_menu_scripts() {
    local menu="$1"

    cat > "$menu/render" <<'EOF'
#!/bin/sh
# Prints the menu lines: id, then checkbox, indented name and description. A
# section's checkbox shows whether all ([x]), some ([-]) or none ([ ]) of
# its blocks are selected.
awk -F '\t' -v selected="$1/selected" '
    BEGIN { while ((getline id < selected) > 0) checked[id] = 1 }
    NR == FNR {
        if ($2 == "block" && $6 != "") {
            total[$6]++
            if (checked[$1]) chosen[$6]++
        }
        next
    }
    {
        if ($2 == "section")
            box = chosen[$1] == total[$1] ? "[x] " : (chosen[$1] ? "[-] " : "[ ] ")
        else
            box = checked[$1] ? "[x] " : "[ ] "
        printf "%s\t%-30s %s\n", $1, $3 box $4, $5
    }
' "$1/lines" "$1/lines"
EOF

    cat > "$menu/toggle" <<'EOF'
#!/bin/sh
# Selects the block when it is not selected, unselects it otherwise. For a
# section (@<module>), selects all its blocks, or unselects them all when
# they all are.
menu="$1"
case "$2" in
    @*)
        awk -F '\t' -v section="$2" '$2 == "block" && $6 == section { print $1 }' \
            "$menu/lines" > "$menu/section"
        if grep -qvxF -f "$menu/selected" "$menu/section"; then
            grep -vxF -f "$menu/selected" "$menu/section" >> "$menu/selected"
        else
            grep -vxF -f "$menu/section" "$menu/selected" > "$menu/selected.new"
            mv "$menu/selected.new" "$menu/selected"
        fi
        ;;
    *)
        if grep -qxF "$2" "$menu/selected"; then
            grep -vxF "$2" "$menu/selected" > "$menu/selected.new"
            mv "$menu/selected.new" "$menu/selected"
        else
            echo "$2" >> "$menu/selected"
        fi
        ;;
esac
EOF

    cat > "$menu/tab" <<'EOF'
#!/bin/sh
# Toggles the block, then prints the fzf actions redrawing the list and
# moving the cursor to the next line (FZF_POS: current line, from 1)
"$1/toggle" "$1" "$2"
echo "reload-sync('$1/render' '$1')+pos($((FZF_POS + 1)))"
EOF

    chmod +x "$menu/render" "$menu/toggle" "$menu/tab"
}

# Shows the blocks menu, with a checkbox per block, and prints the ids of
# the selected blocks (none when nothing is selected). Returns non-zero when
# cancelled (Esc).
#
# Args:
#   profile: The profile name, shown in the menu.
#   selected: The name of an associative array (block id -> 1) of the blocks
#       selected when the menu opens.
_choose_blocks() {
    local profile="$1"
    local -n initial_selection="$2"
    local menu
    menu=$(mktemp -d)
    mkdir "$menu/previews"
    _write_menu_scripts "$menu"
    : > "$menu/selected"
    : > "$menu/lines"

    local -A module_of=() offered=()
    local modules=() id
    _index_modules module_of modules
    for id in "${BLOCK_IDS[@]}"; do
        if _offered "$id"; then
            offered[$id]=1
        fi
    done

    # One "id<TAB>kind<TAB>indent<TAB>name<TAB>description<TAB>section" line
    # per section and offered block. A module with an element named after it
    # shows that element as the head of its blocks; the other modules get a
    # section line, which selects all their blocks.
    local module section head indent name section_blocks
    for module in "${modules[@]}"; do
        section=""
        head=""
        section_blocks=""
        if [ -z "${BLOCK_FUNCTION[$module]}" ]; then
            section="@$module"
            head="    "
        fi

        for id in "${BLOCK_IDS[@]}"; do
            if [ "${module_of[$id]}" != "$module" ] || [ -z "${offered[$id]}" ]; then
                continue
            fi

            # The section line goes before the first block of the module
            if [ -n "$section" ] && [ -z "$section_blocks" ]; then
                printf '%s\tsection\t\t%s\t%s\t%s\n' "$section" "$module" \
                    "${MODULE_DESCRIPTION[$module]}" "$section" >> "$menu/lines"
            fi

            # Names are shown without the prefix of their section or element
            indent="$head"
            name="${id#"$module".}"
            if _is_component "$id"; then
                indent="$head    "
                name="${id#*.}"
            fi
            printf '%s\tblock\t%s\t%s\t%s\t%s\n' "$id" "$indent" "$name" \
                "${BLOCK_DESCRIPTION[$id]}" "$section" >> "$menu/lines"
            section_blocks+=$(printf '  %-26s %s' "$id" "${BLOCK_DESCRIPTION[$id]}")$'\n'

            _block_preview "$id" > "$menu/previews/$id"
            if [ -n "${initial_selection[$id]}" ]; then
                echo "$id" >> "$menu/selected"
            fi
        done

        if [ -n "$section" ] && [ -n "$section_blocks" ]; then
            printf '%s\n%s\n\nTab selects all its blocks, or unselects them all\nwhen they all are:\n\n%s' \
                "$module" "${MODULE_DESCRIPTION[$module]}" "$section_blocks" > "$menu/previews/$section"
        fi
    done

    # Tab updates the selection file, redraws the list and moves down
    local status=0
    "$menu/render" "$menu" | fzf \
            --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Blocks — profile: $profile " \
            --prompt "Blocks > " \
            --header "Tab: select/unselect  Enter: continue  Esc: quit" \
            --preview "cat '$menu/previews/'{1}" --preview-window "right,45%,wrap" \
            --bind "tab:transform('$menu/tab' '$menu' {1})" \
        > /dev/null || status=$?

    if [ "$status" -eq 0 ]; then
        cat "$menu/selected"
    fi
    rm -rf "$menu"
    return "$status"
}

# Shows the blocks that will run, in run order, with why the ones not
# selected in the menu are there. Prints "install" (Enter) or "save" (s, to
# save the selection as a profile); returns non-zero to go back to the
# selection (Esc).
#
# Args:
#   order: The name of the array of the ordered block ids.
#   reasons: The name of an associative array (block id -> why it was added).
_confirm_summary() {
    local -n summary_order="$1"
    local -n summary_reasons="$2"
    local previews
    previews=$(mktemp -d)

    local dim=$'\e[2m' reset=$'\e[0m'
    local lines=() index=0 id why
    for id in "${summary_order[@]}"; do
        index=$((index + 1))
        why=""
        if [ -n "${BLOCK_REQUIRED[$id]}" ]; then
            why="always run"
        elif [ -n "${summary_reasons[$id]}" ]; then
            why="${summary_reasons[$id]}"
        fi
        lines+=("$(printf "%s\t%3d. %-26s $dim%-26s$reset %s" "$id" "$index" "$id" "$why" "${BLOCK_DESCRIPTION[$id]}")")
        _block_preview "$id" > "$previews/$id"
    done

    # --expect prints the key that closed fzf first: empty for Enter, s
    local output status=0
    output=$(printf '%s\n' "${lines[@]}" | fzf --ansi --no-input \
            --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Summary — $(_count "${#summary_order[@]}" block), in run order " \
            --header "Enter: install  s: save as a profile  Esc: back to the selection  ?: show/hide details" \
            --preview "cat '$previews'/{1}" --preview-window "right,45%,wrap,hidden" \
            --bind "?:toggle-preview" \
            --expect s) \
        || status=$?
    rm -rf "$previews"

    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    if [ "${output%%$'\n'*}" = "s" ]; then
        echo "save"
    else
        echo "install"
    fi
}

# Asks for the variant a new profile sets for each config choice: one of its
# variants, or "ask" to ask for it during the setup. Fills the array with the
# set ones.
#
# Args:
#   variants: The name of an associative array receiving the variant of each
#       choice folder (relative to the repository).
_ask_profile_variants() {
    local -n asked_variants="$1"
    local marker dir folder description names file answer current
    while IFS= read -r marker; do
        dir=$(dirname "$marker")
        folder="${dir#"$SETUP_DIR"/}"
        description=$(head -n 1 "$marker")

        names=()
        for file in "$dir"/*; do
            if [ -f "$file" ] && [ ! -L "$file" ]; then
                file=$(basename "$file")
                names+=("${file%.*}")
            fi
        done
        current="${PROFILE_CHOICES[$folder]:-ask}"

        while true; do
            printf "\r\033[K\033[1;34m[i]\033[0m %s (%s or ask) [%s]: " \
                "$description" "${names[*]}" "$current" > /dev/tty
            read -r answer < /dev/tty
            answer="${answer:-$current}"
            if [ "$answer" = "ask" ] || [[ " ${names[*]} " == *" $answer "* ]]; then
                break
            fi
            log_warn "Unknown variant: $answer"
        done

        if [ "$answer" != "ask" ]; then
            asked_variants[$folder]="$answer"
        fi
    done < <(find "$SETUP_DIR" -name .choice -not -path "*/.git/*" | sort)
}

# Saves the blocks selected in the menu as a new local profile (in
# USER_PROFILES_DIR, outside the repository), asking for its name,
# description and variants, and uses its variants for this run. The
# required blocks and the ones the selection needs are not written: they
# come back on their own.
#
# Args:
#   selected: The name of an associative array (block id -> 1) of the blocks
#       selected in the menu.
#   profile: The name of the variable holding the current profile name, set
#       to the new one.
_save_profile() {
    local -n saved_selection="$1"
    local -n current_profile="$2"

    local name="" question answer
    while true; do
        printf "\r\033[K\033[1;34m[i]\033[0m Profile name (letters, digits, - and _; Enter to cancel): " > /dev/tty
        read -r name < /dev/tty
        if [ -z "$name" ]; then
            log_info "Profile not saved."
            return 0
        fi
        if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]] || [ "$name" = "none" ]; then
            log_warn "Invalid profile name: $name"
            continue
        fi

        question=""
        if [ -f "$USER_PROFILES_DIR/$name.profile" ]; then
            question="Your profile $name already exists, replace it?"
        elif [ -f "$PROFILES_DIR/$name.profile" ]; then
            question="The repository has a profile $name, yours will be used instead on this machine. Continue?"
        fi
        if [ -n "$question" ]; then
            answer="n"
            printf "\r\033[K\033[1;33m[!]\033[0m %s [y/N]: " "$question" > /dev/tty
            read -r answer < /dev/tty
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        break
    done

    local description=""
    printf "\r\033[K\033[1;34m[i]\033[0m Description (shown in the profile menu): " > /dev/tty
    read -r description < /dev/tty

    local -A variants=()
    _ask_profile_variants variants

    local file="$USER_PROFILES_DIR/$name.profile" id folder
    mkdir -p "$USER_PROFILES_DIR"
    {
        echo "# ${description:-$name}"
        for id in "${BLOCK_IDS[@]}"; do
            if [ -n "${saved_selection[$id]}" ]; then
                echo "block $id"
            fi
        done
        if [ "${#variants[@]}" -gt 0 ]; then
            echo
            for folder in $(printf '%s\n' "${!variants[@]}" | sort); do
                echo "choice $folder ${variants[$folder]}"
            done
        fi
    } > "$file"

    # This run uses the new profile's variants
    PROFILE_CHOICES=()
    for folder in "${!variants[@]}"; do
        PROFILE_CHOICES[$folder]="${variants[$folder]}"
    done
    current_profile="$name"

    log_success "Profile saved: ${file/#$HOME/\~}"
}

# Adds to the selection the blocks the selected ones need, recursively, when
# they apply to this machine, and records why each one was added.
#
# Args:
#   selection: The name of an associative array (block id -> 1).
#   reasons: The name of an associative array receiving "needed by <block>"
#       for each added block.
_add_needed_blocks() {
    local -n wanted="$1"
    local -n added_reasons="$2"
    local added=1 id need
    while [ "$added" -eq 1 ]; do
        added=0
        for id in "${!wanted[@]}"; do
            for need in ${BLOCK_NEEDS[$id]}; do
                if [ -z "${wanted[$need]}" ] && block_available "$need"; then
                    wanted[$need]=1
                    added_reasons[$need]="needed by $id"
                    added=1
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

# Drops the blocks that run before the resume block. Stops when it is not
# part of the run.
#
# Args:
#   order: The name of the array of the ordered block ids.
#   resume: The block to resume from.
_resume_from() {
    local -n resumed="$1"
    local index
    for index in "${!resumed[@]}"; do
        if [ "${resumed[index]}" = "$2" ]; then
            resumed=("${resumed[@]:index}")
            return 0
        fi
    done
    log_error "Cannot resume from $2: it is not part of this run."
    exit 1
}

# Completes a selection with the blocks it needs and puts it in run order,
# from the resume block when there is one.
#
# Args:
#   selection: The name of an associative array (block id -> 1).
#   reasons: The name of an associative array receiving why each block was
#       added.
#   order: The name of the array receiving the ordered ids.
#   resume: The block to resume from, or nothing.
_plan() {
    _add_needed_blocks "$1" "$2"
    _run_order "$1" "$3"
    if [ -n "$4" ]; then
        _resume_from "$3" "$4"
    fi
}

# Prints the blocks by module, with how they are offered on this machine,
# and the profiles.
_list() {
    local -A module_of=()
    local modules=() module id label state name
    _index_modules module_of modules

    printf '\nBlocks, by module (modules/<module>.sh):\n'
    for module in "${modules[@]}"; do
        printf '\n  %s — %s\n' "$module" "${MODULE_DESCRIPTION[$module]}"
        for id in "${BLOCK_IDS[@]}"; do
            if [ "${module_of[$id]}" != "$module" ]; then
                continue
            fi

            state=""
            if ! block_available "$id"; then
                state="not for this machine"
            elif [ -n "${BLOCK_REQUIRED[$id]}" ]; then
                state="always run"
            elif ! _offered "$id"; then
                state="installed with ${id%%.*}"
            fi

            label="$id"
            if _is_component "$id"; then
                label="  $id"
            fi
            printf '    %-28s %s' "$label" "${BLOCK_DESCRIPTION[$id]}"
            if [ -n "$state" ]; then
                printf ' \033[2m(%s)\033[0m' "$state"
            fi
            printf '\n'
        done
    done

    printf '\nProfiles (./setup.sh -p <name>; local ones in %s):\n\n' "${USER_PROFILES_DIR/#$HOME/\~}"
    for name in $(_profile_names); do
        printf '  %-16s %s\n' "$name" "$(_profile_description "$name")"
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

    local -A selection=() reasons=()
    local order=() id

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

        _plan selection reasons order "$resume"
        init_ui
        for id in "${order[@]}"; do
            if [ -n "${reasons[$id]}" ]; then
                log_info "Adding $id (${reasons[$id]})"
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

        # Selected when the menu opens: the blocks of the profile, then the
        # last selection when coming back from the summary
        local -A selected=()
        for id in "${BLOCK_IDS[@]}"; do
            if _offered "$id" && _in_profile "$id"; then
                selected[$id]=1
            fi
        done

        while true; do
            local chosen
            if ! chosen=$(_choose_blocks "$profile" selected); then
                log_info "Setup cancelled."
                exit 0
            fi

            selected=()
            selection=()
            reasons=()
            order=()
            for id in $chosen; do
                selected[$id]=1
                selection[$id]=1
            done
            for id in "${BLOCK_IDS[@]}"; do
                if [ -n "${BLOCK_REQUIRED[$id]}" ] && block_available "$id"; then
                    selection[$id]=1
                fi
            done

            _plan selection reasons order "$resume"

            # The summary shows again after saving a profile; Esc goes back
            # to the selection
            local action=""
            while action=$(_confirm_summary order reasons) && [ "$action" = "save" ]; do
                _save_profile selected profile
            done
            if [ "$action" = "install" ]; then
                break
            fi
        done

        init_ui
    fi

    if [ "${#order[@]}" -eq 0 ]; then
        log_warn "No block to run."
        exit 0
    fi

    log_info "Running $(_count "${#order[@]}" block): ${order[*]}"
    printf "\n"

    for id in "${order[@]}"; do
        run_block "$id"
    done

    sleep 0.5
    log_success "Setup completed successfully! Please reboot."
}

main "$@"
