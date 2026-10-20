#!/bin/bash

# Initializes the user interface for the setup process.
init_ui() {
    tput civis
    tput clear
    local lines=$(tput lines)

    tput csr 0 $((lines - 2))

    for ((i=0; i<$((lines - 2)); i++)); do
        echo ""
    done

    trap restore_ui EXIT
}

# Restores the terminal to its normal state.
restore_ui() {
    local lines=$(tput lines)

    tput csr 0 $((lines - 1))
    tput cup $((lines - 1)) 0
    printf "\n"
    tput cnorm
}

# Executes a command in the background with a loading spinner.
#
# Args:
#   msg: The description of the task being executed.
#   ...: The command and its arguments.
run_task() {
    local msg="$1"
    shift

    "$@" >/tmp/setup.log 2>&1 &
    local pid=$!

    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local num_frames=${#frames[@]}
    local i=0
    local lines=$(tput lines)

    while kill -0 "$pid" 2>/dev/null; do
        tput sc
        tput cup $((lines - 1)) 0
        printf "\033[1;36m%s\033[0m %s...\033[K" "${frames[i]}" "$msg"
        tput rc
        i=$(( (i + 1) % num_frames ))
        sleep 0.1
    done

    # Le « || » empêche set -e de tuer le script si wait échoue :
    # on récupère le code nous-mêmes pour pouvoir afficher l'erreur.
    local status=0
    wait "$pid" || status=$?

    tput sc
    tput cup $((lines - 1)) 0
    printf "\033[K"
    tput rc

    if [ "$status" -eq 0 ]; then
        printf "\033[1;32m✔\033[0m  %s\n\n" "$msg"
        return 0
    fi

    # Where the failed function is defined
    local fn line file
    read -r fn line file < <(shopt -s extdebug; declare -F "$1") || true
    local where="${fn:-$1}"
    if [ -n "$file" ]; then
        where="$fn, ${file#"$SETUP_DIR"/}:$line"
    fi
    printf "\033[1;31m✖\033[0m  %s \033[2m(code %d — %s)\033[0m\n" "$msg" "$status" "$where"
    printf "\033[2m   ── fin de /tmp/setup.log ──\033[0m\n"
    tail -n 25 /tmp/setup.log | sed 's/^/   │ /'
    printf "\n"
    exit "$status"
}

# Prompts the user for secure input (like passwords) directly via the TTY.
#
# Args:
#   prompt_msg: The question or prompt to display to the user.
#   return_var: The name of the variable where the input will be stored.
getpass() {
    local prompt_msg="$1"
    declare -n ref_var="$2"

    printf "\r\033[K\033[1;34m[i]\033[0m %s " "$prompt_msg" > /dev/tty
    read -s ref_var < /dev/tty
    printf "\n" > /dev/tty
}

# Prints an informational message to the standard output.
#
# Args:
#   msg: The message to display.
log_info() {
    printf "\r\033[K\033[1;34m[i]\033[0m %s\n" "$1" > /dev/tty
}

# Prints a success message to standard output.
#
# Args:
#   msg: Success message to display.
log_success() {
    printf "\r\033[K\033[1;32m[✔]\033[0m %s\n" "$1" > /dev/tty
}

# Prints a warning message to standard output.
#
# Args:
#   msg: Warning message to display.
log_warn() {
    printf "\r\033[K\033[1;33m[!]\033[0m %s\n" "$1" > /dev/tty
}

# Prints an error message to the standard output.
#
# Args:
#   msg: The error message to display.
log_error() {
    printf "\r\033[K\033[1;31m[✖]\033[0m %s\n" "$1" > /dev/tty
}

# Asks a yes/no question, yes being the answer to Enter, or no when the
# default is "no".
#
# Args:
#   question: The question to display.
#   default: "no" to make no the answer to Enter (default: "yes").
confirm() {
    local answer="" choices="[Y/n]"
    if [ "${2:-yes}" = no ]; then
        choices="[y/N]"
    fi
    printf "\r\033[K\033[1;34m[i]\033[0m %s %s: " "$1" "$choices" > /dev/tty
    read -r answer < /dev/tty

    if [ "${2:-yes}" = no ]; then
        [[ "$answer" =~ ^[Yy]$ ]]
    else
        [[ ! "$answer" =~ ^[Nn]$ ]]
    fi
}

# Returns success on a 64-bit ARM CPU (e.g. Apple Silicon with Asahi Linux),
# whose repositories (Arch Linux ARM) lack some x86_64 packages.
is_arm() {
    [ "$(uname -m)" = "aarch64" ]
}

# Returns success inside a virtual machine.
in_vm() {
    systemd-detect-virt --vm --quiet
}

# Installs a package using pacman.
#
# Args:
#   pkg: The name of the package to install.
install_pkg() {
    local pkg="$1"
    log_info "Checking and installing: $pkg"
    sudo pacman -S --needed --noconfirm "$pkg"
}

# Installs a package from the AUR using yay.
#
# Args:
#   pkg: The name of the AUR package to install.
install_aur_pkg() {
    local pkg="$1"
    log_info "Checking and installing AUR package: $pkg"
    yay -S --needed --noconfirm "$pkg"
}

# Creates a symbolic link and safely backs up existing configurations.
#
# Args:
#   src: Source file or directory path.
#   dest: Destination path for the symbolic link.
link_config() {
    local src="$1"
    local dest="$2"

    local src_name=$(basename "$src")
    local short_src="${src/$HOME/\~}"
    local short_dest="${dest/$HOME/\~}"

    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        log_warn "Archiving configuration:
      ├─ old: $short_dest
      └─ bak: ${short_dest}.bak"
        mv "$dest" "${dest}.bak"
    elif [ -L "$dest" ]; then
        rm "$dest"
    fi

    log_info "Linking configuration ($src_name):
      ├─ src: $short_src
      └─ dst: $short_dest"
    ln -s "$src" "$dest"
}

# Copies a configuration into the home folder, for a file edited on each
# machine: the edits stay out of the repository. An identical copy is left
# as is, a link (an earlier deployment) is replaced, and a different file is
# kept as .bak, or as .bak.1, .bak.2... so that no backup is overwritten.
#
# Args:
#   src: The file or folder to copy.
#   dest: Where to copy it.
copy_config() {
    local src="$1"
    local dest="$2"

    local src_name=$(basename "$src")
    local short_src="${src/$HOME/\~}"
    local short_dest="${dest/$HOME/\~}"

    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ]; then
        rm "$dest"
    elif [ -e "$dest" ]; then
        if diff -rq "$src" "$dest" > /dev/null 2>&1; then
            log_info "Configuration already up to date: $short_dest"
            return
        fi
        local backup="${dest}.bak" n=1
        while [ -e "$backup" ] || [ -L "$backup" ]; do
            backup="${dest}.bak.$n"
            n=$((n + 1))
        done
        log_warn "Archiving configuration:
      ├─ old: $short_dest
      └─ bak: ${backup/$HOME/\~}"
        mv "$dest" "$backup"
    fi

    log_info "Copying configuration ($src_name):
      ├─ src: $short_src
      └─ dst: $short_dest"
    cp -R "$src" "$dest"
}

# ==========================================
# CONFIG VARIANTS
# ==========================================
# A choice is a folder of a config holding a .choice file (its description
# on the first line) and its variants: files, named without their
# extension, or folders. The chosen variant is linked in the same folder as
# selected (a folder) or selected.<ext> (a file), and the config includes
# that link. When the source of a config is itself a choice, each variant is
# a whole version of the config, and the config is linked to the selection.
# The variants are picked in the configs menu (or set by the profile) and
# linked when the config is deployed.

# Variant chosen for each choice folder (relative to the repository): set by
# the profile (choice <folder> <variant>), then in the configs menu.
declare -gA CHOSEN_VARIANTS=()

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

# Prints the name of the selection link of a variant: selected for a
# folder, selected.<ext> for a file.
#
# Args:
#   dir: The choice folder.
#   entry: The name of the variant file or folder in it.
_selection_name() {
    if [ -f "$1/$2" ] && [[ "$2" == *.* ]]; then
        echo "selected.${2##*.}"
    else
        echo "selected"
    fi
}

# Links a variant of a choice folder as selected or selected.<ext>,
# replacing the previous selection.
#
# Args:
#   dir: The choice folder.
#   entry: The name of the variant file or folder in it.
_link_variant() {
    local dir="$1"
    local entry="$2"

    _clear_selection "$dir"
    ln -sn "$entry" "$dir/$(_selection_name "$dir" "$entry")"
}

# Prints the variants of a choice folder: its files without their extension
# and its folders, the selection link excepted.
#
# Args:
#   folder: The choice folder, relative to the repository.
choice_variants() {
    local entry name
    for entry in "$SETUP_DIR/$1"/*; do
        if [ -L "$entry" ]; then
            continue
        fi
        name="${entry##*/}"
        if [ -d "$entry" ]; then
            echo "$name"
        elif [ -f "$entry" ]; then
            echo "${name%.*}"
        fi
    done
}

# Prints the name of the file or folder of a variant in its choice folder,
# or nothing when there is none.
#
# Args:
#   folder: The choice folder, relative to the repository.
#   variant: The variant name.
_variant_entry() {
    local entry name
    for entry in "$SETUP_DIR/$1"/*; do
        if [ -L "$entry" ]; then
            continue
        fi
        name="${entry##*/}"
        if { [ -d "$entry" ] && [ "$name" = "$2" ]; } \
            || { [ -f "$entry" ] && [ "${name%.*}" = "$2" ]; }; then
            echo "$name"
            return 0
        fi
    done
}

# Prints the variant to use for a choice folder: the chosen one, else the
# linked one, else "default", else the first one.
#
# Args:
#   folder: The choice folder, relative to the repository.
choice_variant() {
    local folder="$1"
    if [ -n "${CHOSEN_VARIANTS[$folder]}" ]; then
        echo "${CHOSEN_VARIANTS[$folder]}"
        return
    fi

    local link name
    for link in "$SETUP_DIR/$folder"/selected "$SETUP_DIR/$folder"/selected.*; do
        if [ -L "$link" ] && [ -e "$link" ]; then
            name=$(readlink "$link")
            if [ -d "$link" ]; then
                echo "$name"
            else
                echo "${name%.*}"
            fi
            return
        fi
    done

    local variants
    variants=$(choice_variants "$folder")
    if grep -qx "default" <<< "$variants"; then
        echo "default"
    else
        head -n 1 <<< "$variants"
    fi
}

# ==========================================
# BLOCKS
# ==========================================
# Each step of the setup is a block, declared by its module with `block`
# when setup.sh sources it. A block is either a general element (desktop,
# shell, neovim...) or one of its components, <element>.<component>
# (desktop.sddm). setup.sh offers the elements and their optional components
# in a menu and adds the blocks they need. The required blocks run first,
# then each block runs after the ones it needs (--needs) or must follow
# (--after), in declaration order otherwise.

declare -ga BLOCK_IDS=()
declare -gA BLOCK_FUNCTION=() BLOCK_DESCRIPTION=() BLOCK_SOURCE=()
declare -gA BLOCK_REQUIRED=() BLOCK_INTERACTIVE=() BLOCK_IF=() BLOCK_UNLESS=()
declare -gA BLOCK_NEEDS=() BLOCK_AFTER=()
declare -gA MODULE_DESCRIPTION=()

# Describes the module calling it (modules/<name>.sh), shown as the heading
# of its blocks in the menu.
#
# Args:
#   description: What the module installs.
module() {
    MODULE_DESCRIPTION[$(basename "${BASH_SOURCE[1]}" .sh)]="$1"
}

# Declares a block of the setup.
#
# Args:
#   id: The block id: an element (python) or a component of an element
#       (desktop.sddm). A component its element needs is installed with it
#       and not offered in the menu; the other components are optional.
#   function: The function that runs the block. The comment above it is
#       shown in the menu preview.
#   description: One line shown in the menu and while the block runs.
#   ...: Options:
#       --required          Always runs, not offered in the menu.
#       --interactive       Runs in the foreground instead of behind the
#                           spinner, for blocks that ask questions.
#       --if <function>     Only offered when the function succeeds.
#       --unless <function> Only offered when the function fails.
#       --needs <id>        A block without which this one would break (its
#                           config runs that block's commands), added to
#                           the selection when it applies to the machine,
#                           and run before this one. Can be repeated.
#       --after <id>        A block to run before this one when it is
#                           selected too, without adding it. Can be
#                           repeated.
block() {
    local id="$1"
    if [ -n "${BLOCK_FUNCTION[$id]}" ]; then
        log_error "Block declared twice: $id"
        exit 1
    fi

    BLOCK_IDS+=("$id")
    BLOCK_FUNCTION[$id]="$2"
    BLOCK_DESCRIPTION[$id]="$3"
    BLOCK_SOURCE[$id]="${BASH_SOURCE[1]}"
    shift 3

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --required) BLOCK_REQUIRED[$id]=1 ;;
            --interactive) BLOCK_INTERACTIVE[$id]=1 ;;
            --if) BLOCK_IF[$id]="$2"; shift ;;
            --unless) BLOCK_UNLESS[$id]="$2"; shift ;;
            --needs) BLOCK_NEEDS[$id]+="$2 "; shift ;;
            --after) BLOCK_AFTER[$id]+="$2 "; shift ;;
            *) log_error "Unknown option for block $id: $1"; exit 1 ;;
        esac
        shift
    done
}

# Returns success when a block applies to this machine (its --if and
# --unless conditions).
#
# Args:
#   id: The block id.
block_available() {
    local id="$1"
    if [ -n "${BLOCK_IF[$id]}" ] && ! "${BLOCK_IF[$id]}"; then
        return 1
    fi
    if [ -n "${BLOCK_UNLESS[$id]}" ] && "${BLOCK_UNLESS[$id]}"; then
        return 1
    fi
}

# Prints the comment written above a function, in the file declaring it.
#
# Args:
#   function: The function name.
function_doc() {
    local fn line file
    read -r fn line file < <(shopt -s extdebug; declare -F "$1") || true
    if [ -z "$file" ]; then
        return 0
    fi
    awk -v fn="$fn" '
        $0 ~ "^" fn "\\(\\)" { printf "%s", doc; exit }
        /^#/ { sub(/^# ?/, ""); doc = doc $0 "\n"; next }
        { doc = "" }
    ' "$file"
}

# Prints the comment written above the function of a block.
#
# Args:
#   id: The block id.
block_doc() {
    function_doc "${BLOCK_FUNCTION[$1]}"
}

# Runs a block: behind the spinner, or in the foreground when interactive.
#
# Args:
#   id: The block id.
run_block() {
    local id="$1"
    local description="${BLOCK_DESCRIPTION[$id]}"

    if [ -z "${BLOCK_INTERACTIVE[$id]}" ]; then
        run_task "$description" "${BLOCK_FUNCTION[$id]}"
        return
    fi

    log_info "$description"
    "${BLOCK_FUNCTION[$id]}"
    printf "\033[1;32m✔\033[0m  %s\n\n" "$description"
}

# ==========================================
# CONFIGS
# ==========================================
# A config of the repository is deployed as a symbolic link from the home
# folder, or as a copy (--copy), declared with `config` by the module of the
# program it configures.
# setup.sh offers the configs of the blocks it runs in a menu, adds the
# blocks and configs they need, and deploys them after all the blocks.
# With -c, it offers only the given configs whose program is installed.

declare -ga CONFIG_IDS=()
declare -gA CONFIG_SOURCE=() CONFIG_TARGET=() CONFIG_DESCRIPTION=() CONFIG_BLOCK=()
declare -gA CONFIG_PROGRAM=() CONFIG_NEEDS=() CONFIG_NEEDS_CONFIG=() CONFIG_THEN=()
declare -gA CONFIG_COPY=() CONFIG_INTERACTIVE=()

# Declares a config the setup can deploy.
#
# Args:
#   id: The config id (e.g. waybar).
#   source: Its path in the repository (e.g. .config/waybar).
#   target: Where it is linked or copied, from the home folder (e.g.
#       .config/waybar).
#   description: One line shown in the menu.
#   ...: Options:
#       --block <id>         The block installing the program it configures:
#                            the config is offered when that block runs.
#       --program <command>  The command of that program: with -c, the
#                            config is offered only when it is installed
#                            (or when its block runs).
#       --needs <id>         A block without which this config would break
#                            (it runs that block's commands), added with it.
#                            Can be repeated.
#       --needs-config <id>  A config without which this one would break (it
#                            uses that config's files), added with it. Can
#                            be repeated.
#       --copy               Copies the config instead of linking it, for a
#                            file edited on each machine (see copy_config).
#       --interactive        Deploys it in the foreground instead of behind
#                            the spinner, for a --then function that asks
#                            questions.
#       --then <function>    Runs once it is deployed (e.g. installs plugins).
config() {
    local id="$1"
    if [ -n "${CONFIG_SOURCE[$id]}" ]; then
        log_error "Config declared twice: $id"
        exit 1
    fi

    CONFIG_IDS+=("$id")
    CONFIG_SOURCE[$id]="$2"
    CONFIG_TARGET[$id]="$3"
    CONFIG_DESCRIPTION[$id]="$4"
    shift 4

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --block) CONFIG_BLOCK[$id]="$2"; shift ;;
            --program) CONFIG_PROGRAM[$id]="$2"; shift ;;
            --needs) CONFIG_NEEDS[$id]+="$2 "; shift ;;
            --needs-config) CONFIG_NEEDS_CONFIG[$id]+="$2 "; shift ;;
            --copy) CONFIG_COPY[$id]=1 ;;
            --interactive) CONFIG_INTERACTIVE[$id]=1 ;;
            --then) CONFIG_THEN[$id]="$2"; shift ;;
            *) log_error "Unknown option for config $id: $1"; exit 1 ;;
        esac
        shift
    done
}

# Prints the choice folders of a config (its variants), relative to the
# repository.
#
# Args:
#   id: The config id.
config_choices() {
    local source="$SETUP_DIR/${CONFIG_SOURCE[$1]}"
    if [ ! -d "$source" ]; then
        return 0
    fi

    local marker
    while IFS= read -r marker; do
        marker="${marker%/.choice}"
        echo "${marker#"$SETUP_DIR"/}"
    done < <(find "$source" -name .choice | sort)
}

# Deploys a config: links the variant to use for each of its choices, links
# the config into the home folder (an existing one is kept as .bak), or
# copies it with --copy, then runs its --then function. A config whose
# source is a choice is linked to its selected variant, or a copy of it.
#
# Args:
#   id: The config id.
deploy_config() {
    local id="$1"
    local folder variant entry
    while IFS= read -r folder; do
        variant=$(choice_variant "$folder")
        entry=$(_variant_entry "$folder" "$variant")
        if [ -z "$entry" ]; then
            log_warn "${folder#.config/} has no variant $variant"
            continue
        fi
        log_info "Using the $variant variant of ${folder#.config/}"
        _link_variant "$SETUP_DIR/$folder" "$entry"
    done < <(config_choices "$id")

    local source="$SETUP_DIR/${CONFIG_SOURCE[$id]}"
    if [ -f "$source/.choice" ]; then
        entry=$(_variant_entry "${CONFIG_SOURCE[$id]}" "$(choice_variant "${CONFIG_SOURCE[$id]}")")
        if [ -n "${CONFIG_COPY[$id]}" ]; then
            source="$source/$entry"
        else
            source="$source/$(_selection_name "$source" "$entry")"
        fi
    fi

    if [ -n "${CONFIG_COPY[$id]}" ]; then
        copy_config "$source" "$HOME/${CONFIG_TARGET[$id]}"
    else
        link_config "$source" "$HOME/${CONFIG_TARGET[$id]}"
    fi

    if [ -n "${CONFIG_THEN[$id]}" ]; then
        "${CONFIG_THEN[$id]}"
    fi
}

# Deploys a config: behind the spinner, or in the foreground when
# interactive.
#
# Args:
#   id: The config id.
run_config() {
    local id="$1"
    local description="Config $id: ${CONFIG_DESCRIPTION[$id]}"

    if [ -z "${CONFIG_INTERACTIVE[$id]}" ]; then
        run_task "$description" deploy_config "$id"
        return
    fi

    log_info "$description"
    deploy_config "$id"
    printf "\033[1;32m✔\033[0m  %s\n\n" "$description"
}
