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

# Block and config patterns of the chosen profile (its variants go in
# CHOSEN_VARIANTS)
PROFILE_BLOCKS=()
PROFILE_CONFIGS=()

# Prints the help message and exits.
_show_help() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Without -b, -m or -c, asks for a profile, then for the blocks to run and the
configs to deploy (the profile's ones selected), and shows what will run
before installing it. The blocks and configs they need are added, every
block runs after the ones it needs, and the configs are deployed after the
blocks.

Options:
  -p, --profile <name>   Use this profile instead of asking for one (from
                         ~/.local/share/arch-setup/profiles, where the menu
                         saves them, or else from profiles/)
  -b, --block <pattern>  Run only the matching blocks and the ones they need,
                         without the menus (e.g. neovim, "app.*"); can be
                         repeated
  -m, --module <name>    Same for the blocks of modules/<name>.sh; can be
                         repeated
  -c, --config <pattern> Show only the matching configs whose program is
                         installed in the configs menu, to pick their
                         variants, and deploy them, without running any
                         block nor adding the configs they need (e.g.
                         waybar); can be repeated
  -r, --resume <block>   Skip the blocks that run before this one
  -l, --list             List the blocks, the configs and the profiles
  -h, --help             Show this help message

Examples:
  ./setup.sh -p desktop
  ./setup.sh -m wallpapers
  ./setup.sh -b neovim -b "app.*"
  ./setup.sh -c hypr -c waybar
  ./setup.sh -p full --resume shell
EOF
    exit 0
}

# Sources the core, then every module, which declares its blocks and configs.
_load_modules() {
    source "$SETUP_DIR/modules/core.sh"

    local module
    for module in "$SETUP_DIR"/modules/*.sh; do
        if [ "$(basename "$module")" != "core.sh" ]; then
            source "$module"
        fi
    done
}

# Stops on a mistake in the declarations of a module: a block or config
# referring to one that does not exist, a config without its --block, its
# --program, its file or its --then function.
_check_declarations() {
    local id other folder names duplicates
    for id in "${BLOCK_IDS[@]}"; do
        for other in ${BLOCK_NEEDS[$id]} ${BLOCK_AFTER[$id]}; do
            if [ -z "${BLOCK_FUNCTION[$other]}" ]; then
                log_error "Block $id refers to an unknown block: $other"
                exit 1
            fi
        done
    done

    for id in "${CONFIG_IDS[@]}"; do
        if [ -z "${CONFIG_BLOCK[$id]}" ]; then
            log_error "Config $id has no --block"
            exit 1
        fi
        if [ -z "${CONFIG_PROGRAM[$id]}" ]; then
            log_error "Config $id has no --program"
            exit 1
        fi
        for other in ${CONFIG_BLOCK[$id]} ${CONFIG_NEEDS[$id]}; do
            if [ -z "${BLOCK_FUNCTION[$other]}" ]; then
                log_error "Config $id refers to an unknown block: $other"
                exit 1
            fi
        done
        for other in ${CONFIG_NEEDS_CONFIG[$id]}; do
            if [ -z "${CONFIG_SOURCE[$other]}" ]; then
                log_error "Config $id refers to an unknown config: $other"
                exit 1
            fi
        done
        if [ ! -e "$SETUP_DIR/${CONFIG_SOURCE[$id]}" ]; then
            log_error "Config $id: ${CONFIG_SOURCE[$id]} does not exist"
            exit 1
        fi
        if [ -n "${CONFIG_THEN[$id]}" ] && ! declare -F "${CONFIG_THEN[$id]}" > /dev/null; then
            log_error "Config $id: unknown --then function ${CONFIG_THEN[$id]}"
            exit 1
        fi

        # A variant name has to point to one file or folder of its choice
        while IFS= read -r folder; do
            names=$(choice_variants "$folder")
            duplicates=$(sort <<< "$names" | uniq -d | tr '\n' ' ')
            if [ -z "$names" ]; then
                log_error "Config $id: $folder has no variant"
                exit 1
            fi
            if [ -n "$duplicates" ]; then
                log_error "Config $id: $folder has a file and a folder named ${duplicates% }"
                exit 1
            fi
        done < <(config_choices "$id")
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

# Prints the ids of the configs matching shell patterns (e.g. "*").
#
# Args:
#   ...: The patterns.
_matching_configs() {
    local id pattern
    for id in "${CONFIG_IDS[@]}"; do
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

# Reads a profile: its block and config patterns into PROFILE_BLOCKS and
# PROFILE_CONFIGS, and its variants into CHOSEN_VARIANTS. Warns about the
# patterns matching nothing and the variants that do not exist.
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
            config)
                PROFILE_CONFIGS+=("$arg")
                if [ -z "$(_matching_configs "$arg")" ]; then
                    log_warn "$name.profile: no config matches $arg"
                fi
                ;;
            choice)
                if [ ! -f "$SETUP_DIR/$arg/.choice" ]; then
                    log_warn "$name.profile: $arg is not a choice folder"
                elif ! choice_variants "$arg" | grep -qxF "$value"; then
                    log_warn "$name.profile: $arg has no variant $value"
                else
                    CHOSEN_VARIANTS[$arg]="$value"
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

# Returns success when the profile selects a config.
#
# Args:
#   id: The config id.
_in_profile_configs() {
    local pattern
    for pattern in "${PROFILE_CONFIGS[@]}"; do
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

# Prints the menu preview of a config: where it is linked, the block of its
# program, what it needs and what it runs once linked.
#
# Args:
#   id: The config id.
#   added: What becomes of the blocks and configs it needs (default: "added
#       automatically").
_config_preview() {
    local id="$1"
    local added="${2:-added automatically}"
    printf '%s → ~/%s\n%s\n\n' "$id" "${CONFIG_TARGET[$id]}" "${CONFIG_DESCRIPTION[$id]}"
    printf 'Links %s from the repository; an existing config\nis kept as .bak.\n' "${CONFIG_SOURCE[$id]}"
    printf '\nOffered when this block runs: %s\n' "${CONFIG_BLOCK[$id]}"
    if [ -n "${CONFIG_NEEDS[$id]}" ]; then
        printf '\nNeeds the blocks (%s): %s\n' "$added" "${CONFIG_NEEDS[$id]% }"
    fi
    if [ -n "${CONFIG_NEEDS_CONFIG[$id]}" ]; then
        printf '\nNeeds the configs (%s): %s\n' "$added" "${CONFIG_NEEDS_CONFIG[$id]% }"
    fi
    if [ -n "${CONFIG_THEN[$id]}" ]; then
        printf '\nOnce linked:\n%s\n' "$(function_doc "${CONFIG_THEN[$id]}")"
    fi
}

# Prints the menu preview of a config variant: what it changes and its
# values.
#
# Args:
#   folder: The choice folder, relative to the repository.
_variant_preview() {
    printf '%s\n%s\n\n' "${1##*/}" "$(head -n 1 "$SETUP_DIR/$1/.choice")"
    printf 'Variants (←/→ to change):\n'
    choice_variants "$1" | sed 's/^/  /'
    printf '\nFiles: %s/\n' "$1"
}

# Prints the variants a config will use, e.g. "keybinds: vim, keyboard:
# default".
#
# Args:
#   id: The config id.
_config_variants_text() {
    local folder text=""
    while IFS= read -r folder; do
        text+="${text:+, }${folder##*/}: $(choice_variant "$folder")"
    done < <(config_choices "$1")
    echo "$text"
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
        printf 'none\t%-16s %s\t\n' "none" "Nothing selected"
        for name in $(_profile_names); do
            printf '%s\t%-16s %s\t%s\n' "$name" "$name" \
                "$(_profile_description "$name")" "$(_profile_file "$name")"
        done
    } | fzf --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Profile " --prompt "Profile > " \
            --header "Enter: choose  Esc: quit" \
            --preview "cat {3} 2>/dev/null || echo 'Nothing selected.'" \
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

# Writes the scripts of the configs menu into its working folder: render
# prints the configs with their checkbox and, under them, their variants
# with their value; toggle selects or unselects a config; cycle changes a
# variant; key runs Tab, left or right on the line under the cursor. fzf
# runs them with the user's shell, so they are standalone sh scripts.
#
# Args:
#   menu: The working folder of the menu (lines, selected, values,
#       options/, previews/).
_write_config_menu_scripts() {
    local menu="$1"

    cat > "$menu/render" <<'EOF'
#!/bin/sh
# Prints the menu lines: id, then the checkbox and name of a config, or the
# name and value of a variant, under its config
awk -F '\t' -v selected="$1/selected" -v values="$1/values" '
    BEGIN {
        while ((getline id < selected) > 0) checked[id] = 1
        while ((getline line < values) > 0) {
            split(line, field, "\t")
            value[field[1]] = field[2]
        }
    }
    $2 == "config" {
        printf "%s\t%-30s %s\n", $1, (checked[$1] ? "[x] " : "[ ] ") $3, $4
    }
    $2 == "variant" {
        printf "%s\t%-30s %-14s %s\n", $1, "      " $3, "< " value[$1] " >", $4
    }
' "$1/lines"
EOF

    cat > "$menu/toggle" <<'EOF'
#!/bin/sh
# Selects the config when it is not selected, unselects it otherwise
if grep -qxF "$2" "$1/selected"; then
    grep -vxF "$2" "$1/selected" > "$1/selected.new"
    mv "$1/selected.new" "$1/selected"
else
    echo "$2" >> "$1/selected"
fi
EOF

    cat > "$menu/cycle" <<'EOF'
#!/bin/sh
# Changes a variant to its next (1) or previous (-1) value
awk -F '\t' -v id="$2" -v step="$3" -v options="$1/options/$2" '
    BEGIN { while ((getline option < options) > 0) list[count++] = option }
    $1 == id {
        for (i = 0; i < count; i++) if (list[i] == $2) break
        if (i == count) i = 0
        print id "\t" list[(i + step + count) % count]
        next
    }
    { print }
' "$1/values" > "$1/values.new"
mv "$1/values.new" "$1/values"
EOF

    cat > "$menu/key" <<'EOF'
#!/bin/sh
# Runs a key on the line under the cursor: on a config, Tab selects or
# unselects it and moves down; on a variant, Tab and right show its next
# value, left its previous one. Prints the fzf actions redrawing the list
# (FZF_POS: current line, from 1).
menu="$1"
position=$FZF_POS
case "$3" in
    %*)
        if [ "$2" = left ]; then
            "$menu/cycle" "$menu" "$3" -1
        else
            "$menu/cycle" "$menu" "$3" 1
        fi
        ;;
    *)
        if [ "$2" = tab ]; then
            "$menu/toggle" "$menu" "$3"
            position=$((FZF_POS + 1))
        fi
        ;;
esac
echo "reload-sync('$menu/render' '$menu')+pos($position)"
EOF

    chmod +x "$menu/render" "$menu/toggle" "$menu/cycle" "$menu/key"
}

# Shows the configs menu: the given configs, with a checkbox each and their
# variants under them. Prints "config <id>" for each selected config and
# "choice <folder> <variant>" for each variant; returns non-zero to go back
# (Esc).
#
# Args:
#   offered: The name of an array of the config ids to show.
#   selected: The name of an associative array (config id -> 1) of the
#       configs selected when the menu opens.
#   mode: "setup" in the setup menus, where Enter goes to the summary, or
#       "alone" for -c, where Enter deploys the configs alone, without the
#       blocks and configs they need.
_choose_configs() {
    local -n shown_configs="$1"
    local -n initial_configs="$2"
    local keys="Enter: summary  Esc: back to the blocks" added="added automatically"
    if [ "$3" = alone ]; then
        keys="Enter: deploy  Esc: cancel"
        added="not added with -c"
    fi
    local menu
    menu=$(mktemp -d)
    mkdir "$menu/previews" "$menu/options"
    _write_config_menu_scripts "$menu"
    : > "$menu/selected"
    : > "$menu/lines"
    : > "$menu/values"

    # One "id<TAB>kind<TAB>name<TAB>description<TAB>folder" line per config
    # and per variant (id %<n>), the variants under their config
    local id folder variant index=0
    for id in "${shown_configs[@]}"; do
        printf '%s\tconfig\t%s\t%s\t\n' "$id" "$id" "${CONFIG_DESCRIPTION[$id]}" >> "$menu/lines"
        _config_preview "$id" "$added" > "$menu/previews/$id"
        if [ -n "${initial_configs[$id]}" ]; then
            echo "$id" >> "$menu/selected"
        fi

        while IFS= read -r folder; do
            index=$((index + 1))
            variant="%$index"
            printf '%s\tvariant\t%s\t%s\t%s\n' "$variant" "${folder##*/}" \
                "$(head -n 1 "$SETUP_DIR/$folder/.choice")" "$folder" >> "$menu/lines"
            choice_variants "$folder" > "$menu/options/$variant"
            printf '%s\t%s\n' "$variant" "$(choice_variant "$folder")" >> "$menu/values"
            _variant_preview "$folder" > "$menu/previews/$variant"
        done < <(config_choices "$id")
    done

    local status=0
    "$menu/render" "$menu" | fzf --no-input \
            --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Configs to deploy " \
            --header "Tab: select/unselect  ←/→: change a variant  $keys" \
            --preview "cat '$menu/previews/'{1}" --preview-window "right,45%,wrap" \
            --bind "tab:transform('$menu/key' '$menu' tab {1})" \
            --bind "right:transform('$menu/key' '$menu' right {1})" \
            --bind "left:transform('$menu/key' '$menu' left {1})" \
        > /dev/null || status=$?

    if [ "$status" -eq 0 ]; then
        sed 's/^/config /' "$menu/selected"
        awk -F '\t' 'NR == FNR { value[$1] = $2; next }
            $2 == "variant" { print "choice " $5 " " value[$1] }' \
            "$menu/values" "$menu/lines"
    fi
    rm -rf "$menu"
    return "$status"
}

# Shows what will run, in run order: the blocks, then the configs deployed
# after them, with why the ones not selected in the menus are there. Prints
# "install" (Enter) or "save" (s, to save the selection as a profile);
# returns non-zero to go back (Esc).
#
# Args:
#   order: The name of the array of the ordered block ids.
#   reasons: The name of an associative array (block id -> why it was added).
#   configs: The name of the array of the config ids to deploy, in order.
#   config_reasons: The name of an associative array (config id -> why it
#       was added).
_confirm_summary() {
    local -n summary_order="$1"
    local -n summary_reasons="$2"
    local -n summary_configs="$3"
    local -n summary_config_reasons="$4"
    local previews
    previews=$(mktemp -d)

    local dim=$'\e[2m' reset=$'\e[0m'
    local lines=() index=0 id why variants
    for id in "${summary_order[@]}"; do
        index=$((index + 1))
        why=""
        if [ -n "${BLOCK_REQUIRED[$id]}" ]; then
            why="always run"
        elif [ -n "${summary_reasons[$id]}" ]; then
            why="${summary_reasons[$id]}"
        fi
        lines+=("$(printf "%s\t%3d. %-26s $dim%-28s$reset %s" "$id" "$index" "$id" "$why" "${BLOCK_DESCRIPTION[$id]}")")
        _block_preview "$id" > "$previews/$id"
    done

    if [ "${#summary_configs[@]}" -gt 0 ]; then
        lines+=("$(printf -- "-\t     $dim── Configs, deployed after the blocks ──$reset")")
        echo "The configs are linked once all the blocks have run." > "$previews/-"
        for id in "${summary_configs[@]}"; do
            index=$((index + 1))
            why="${summary_config_reasons[$id]}"
            variants=$(_config_variants_text "$id")
            lines+=("$(printf "config:%s\t%3d. %-26s $dim%-28s$reset → ~/%s%s" "$id" "$index" "$id" "$why" \
                "${CONFIG_TARGET[$id]}" "${variants:+  ($variants)}")")
            _config_preview "$id" > "$previews/config:$id"
        done
    fi

    # --expect prints the key that closed fzf first: empty for Enter, s
    local label="$(_count "${#summary_order[@]}" block), $(_count "${#summary_configs[@]}" config)"
    local output status=0
    output=$(printf '%s\n' "${lines[@]}" | fzf --ansi --no-input \
            --delimiter '\t' --with-nth 2 --layout reverse \
            --border rounded --border-label " Summary — $label, in run order " \
            --header "Enter: install  s: save as a profile  Esc: back  ?: show/hide details" \
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

# Saves the blocks and configs selected in the menus, with the variants of
# the configs, as a new local profile (in USER_PROFILES_DIR, outside the
# repository), asking for its name and description. The required blocks
# and the blocks and configs the selection needs are not written: they come
# back on their own.
#
# Args:
#   selected: The name of an associative array (block id -> 1) of the blocks
#       selected in the menu.
#   selected_configs: The name of an associative array (config id -> 1) of
#       the configs selected in the menu.
#   profile: The name of the variable holding the current profile name, set
#       to the new one.
_save_profile() {
    local -n saved_blocks="$1"
    local -n saved_configs="$2"
    local -n current_profile="$3"

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

    local file="$USER_PROFILES_DIR/$name.profile" id folder
    mkdir -p "$USER_PROFILES_DIR"
    {
        echo "# ${description:-$name}"
        for id in "${BLOCK_IDS[@]}"; do
            if [ -n "${saved_blocks[$id]}" ]; then
                echo "block $id"
            fi
        done

        echo
        for id in "${CONFIG_IDS[@]}"; do
            if [ -n "${saved_configs[$id]}" ]; then
                echo "config $id"
            fi
        done

        for id in "${CONFIG_IDS[@]}"; do
            if [ -n "${saved_configs[$id]}" ]; then
                while IFS= read -r folder; do
                    echo "choice $folder $(choice_variant "$folder")"
                done < <(config_choices "$id")
            fi
        done
    } > "$file"

    current_profile="$name"
    log_success "Profile saved: ${file/#$HOME/\~}"
}

# Fills a block selection with the blocks selected in the menu and the
# required ones.
#
# Args:
#   selected: The name of an associative array (block id -> 1) of the blocks
#       selected in the menu.
#   selection: The name of the associative array to fill.
_base_selection() {
    local -n menu_blocks="$1"
    local -n base_blocks="$2"
    local id
    for id in "${!menu_blocks[@]}"; do
        base_blocks[$id]=1
    done
    for id in "${BLOCK_IDS[@]}"; do
        if [ -n "${BLOCK_REQUIRED[$id]}" ] && block_available "$id"; then
            base_blocks[$id]=1
        fi
    done
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

# Prints the configs offered for a block selection: the ones whose
# program's block will run, in declaration order.
#
# Args:
#   selection: The name of an associative array (block id -> 1).
_offered_configs() {
    local -n planned_blocks="$1"
    local id
    for id in "${CONFIG_IDS[@]}"; do
        if [ -n "${planned_blocks[${CONFIG_BLOCK[$id]}]}" ]; then
            echo "$id"
        fi
    done
}

# Completes a config selection with the configs they need, recursively, and
# adds to the block selection the blocks the configs need (their program's
# block and their --needs), recording why each one was added.
#
# Args:
#   configs: The name of an associative array (config id -> 1).
#   config_reasons: The name of an associative array receiving "needed by
#       config <id>" for each added config.
#   selection: The name of an associative array (block id -> 1).
#   reasons: The name of an associative array receiving why each block was
#       added.
_add_config_needs() {
    local -n wanted_configs="$1"
    local -n added_config_reasons="$2"
    local -n config_blocks="$3"
    local -n config_block_reasons="$4"
    local added=1 id need
    while [ "$added" -eq 1 ]; do
        added=0
        for id in "${!wanted_configs[@]}"; do
            for need in ${CONFIG_NEEDS_CONFIG[$id]}; do
                if [ -z "${wanted_configs[$need]}" ]; then
                    wanted_configs[$need]=1
                    added_config_reasons[$need]="needed by config $id"
                    added=1
                fi
            done
        done
    done

    for id in "${!wanted_configs[@]}"; do
        for need in ${CONFIG_BLOCK[$id]} ${CONFIG_NEEDS[$id]}; do
            if [ -z "${config_blocks[$need]}" ] && block_available "$need"; then
                config_blocks[$need]=1
                config_block_reasons[$need]="needed by config $id"
            fi
        done
    done
}

# Prints the configs of a selection, in declaration order.
#
# Args:
#   configs: The name of an associative array (config id -> 1).
_config_order() {
    local -n chosen_configs="$1"
    local id
    for id in "${CONFIG_IDS[@]}"; do
        if [ -n "${chosen_configs[$id]}" ]; then
            echo "$id"
        fi
    done
}

# Prints the blocks by module, with how they are offered on this machine,
# the configs and the profiles.
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

    printf '\nConfigs, deployed after the blocks (./setup.sh -c <pattern>):\n\n'
    for id in "${CONFIG_IDS[@]}"; do
        printf '  %-12s %-28s %s \033[2m(with %s)\033[0m\n' "$id" "~/${CONFIG_TARGET[$id]}" \
            "${CONFIG_DESCRIPTION[$id]}" "${CONFIG_BLOCK[$id]}"
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
    local patterns=() modules=() config_patterns=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -p|--profile) profile="$2"; shift 2 ;;
            -b|--block) patterns+=("$2"); shift 2 ;;
            -m|--module) modules+=("$2"); shift 2 ;;
            -c|--config) config_patterns+=("$2"); shift 2 ;;
            -r|--resume) resume="$2"; shift 2 ;;
            -l|--list) list=true; shift ;;
            -h|--help) _show_help ;;
            *) echo "Unknown parameter: $1"; exit 1 ;;
        esac
    done

    _load_modules
    _check_declarations

    if [ "$list" = true ]; then
        _list
        exit 0
    fi

    if [ -n "$profile" ]; then
        _load_profile "$profile"
    fi

    local -A selection=() reasons=() configs=() config_reasons=()
    local order=() config_order=() id

    if [ "${#patterns[@]}" -gt 0 ] || [ "${#modules[@]}" -gt 0 ] || [ "${#config_patterns[@]}" -gt 0 ]; then
        # Direct mode: the given blocks and the ones they need, without the
        # menus nor the required blocks, and the given configs alone (no
        # block, no needed config), their variants picked in the configs menu
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
        for pattern in "${config_patterns[@]}"; do
            if [ -z "$(_matching_configs "$pattern")" ]; then
                log_warn "No config matches $pattern (see ./setup.sh --list)"
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

        # A config is offered when its program is installed, or installed by
        # the blocks given with it
        local -A running=()
        local offered=() output keyword arg value
        for id in "${order[@]}"; do
            running[$id]=1
        done
        for id in $(_matching_configs "${config_patterns[@]}"); do
            if [ -n "${running[${CONFIG_BLOCK[$id]}]}" ] || command -v "${CONFIG_PROGRAM[$id]}" > /dev/null; then
                offered+=("$id")
            else
                log_warn "Skipping config $id: ${CONFIG_PROGRAM[$id]} is not installed (./setup.sh -b ${CONFIG_BLOCK[$id]} installs it)"
            fi
        done
        if [ "${#offered[@]}" -gt 0 ]; then
            _ensure_fzf
            for id in "${offered[@]}"; do
                configs[$id]=1
            done
            if ! output=$(_choose_configs offered configs alone); then
                log_info "Setup cancelled."
                exit 0
            fi
            configs=()
            while read -r keyword arg value; do
                case "$keyword" in
                    config) configs[$arg]=1 ;;
                    choice) CHOSEN_VARIANTS[$arg]="$value" ;;
                esac
            done <<< "$output"
            mapfile -t config_order < <(_config_order configs)
        fi

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

        # Selected when the menus open: the blocks and configs of the
        # profile, then the last selections when coming back
        local -A selected=() selected_configs=()
        for id in "${BLOCK_IDS[@]}"; do
            if _offered "$id" && _in_profile "$id"; then
                selected[$id]=1
            fi
        done
        for id in "${CONFIG_IDS[@]}"; do
            if _in_profile_configs "$id"; then
                selected_configs[$id]=1
            fi
        done

        # Blocks menu, then configs menu, then summary; Esc goes back a step
        local step="blocks" configs_shown=false chosen output action
        local offered=() keyword arg value
        while true; do
            case "$step" in
                blocks)
                    if ! chosen=$(_choose_blocks "$profile" selected); then
                        log_info "Setup cancelled."
                        exit 0
                    fi
                    selected=()
                    for id in $chosen; do
                        selected[$id]=1
                    done
                    step="configs"
                    ;;

                configs)
                    # The configs offered are the ones of the blocks that will run
                    selection=()
                    reasons=()
                    _base_selection selected selection
                    _add_needed_blocks selection reasons
                    mapfile -t offered < <(_offered_configs selection)

                    if [ "${#offered[@]}" -eq 0 ]; then
                        configs_shown=false
                        step="summary"
                        continue
                    fi
                    configs_shown=true

                    if ! output=$(_choose_configs offered selected_configs setup); then
                        step="blocks"
                        continue
                    fi
                    for id in "${offered[@]}"; do
                        unset 'selected_configs[$id]'
                    done
                    while read -r keyword arg value; do
                        case "$keyword" in
                            config) selected_configs[$arg]=1 ;;
                            choice) CHOSEN_VARIANTS[$arg]="$value" ;;
                        esac
                    done <<< "$output"
                    step="summary"
                    ;;

                summary)
                    selection=()
                    reasons=()
                    configs=()
                    config_reasons=()
                    order=()
                    _base_selection selected selection
                    _add_needed_blocks selection reasons
                    mapfile -t offered < <(_offered_configs selection)
                    for id in "${offered[@]}"; do
                        if [ -n "${selected_configs[$id]}" ]; then
                            configs[$id]=1
                        fi
                    done
                    _add_config_needs configs config_reasons selection reasons
                    _plan selection reasons order "$resume"
                    mapfile -t config_order < <(_config_order configs)

                    # The summary shows again after saving a profile
                    action=""
                    while action=$(_confirm_summary order reasons config_order config_reasons) \
                            && [ "$action" = "save" ]; do
                        _save_profile selected selected_configs profile
                    done
                    if [ "$action" = "install" ]; then
                        break
                    fi
                    if [ "$configs_shown" = true ]; then
                        step="configs"
                    else
                        step="blocks"
                    fi
                    ;;
            esac
        done

        init_ui
    fi

    if [ "${#order[@]}" -eq 0 ] && [ "${#config_order[@]}" -eq 0 ]; then
        log_warn "Nothing to run."
        exit 0
    fi

    if [ "${#order[@]}" -gt 0 ]; then
        log_info "Running $(_count "${#order[@]}" block): ${order[*]}"
        printf "\n"
        for id in "${order[@]}"; do
            run_block "$id"
        done
    fi

    if [ "${#config_order[@]}" -gt 0 ]; then
        log_info "Deploying $(_count "${#config_order[@]}" config): ${config_order[*]}"
        printf "\n"
        for id in "${config_order[@]}"; do
            run_config "$id"
        done
    fi

    sleep 0.5
    log_success "Setup completed successfully! Please reboot."
}

main "$@"
