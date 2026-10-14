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

# ==========================================
# CONFIG VARIANTS
# ==========================================
# A choice is a folder holding a .choice file (its description on the first
# line) and one file per variant. The selected variant is linked as
# selected.<ext> in the same folder, and the configs include that link. The
# module of a config picks its variants with choose_variant; a profile can
# set them (choice <folder> <variant>).

# Variant set by the profile for each choice folder (relative to the
# repository), filled by setup.sh.
declare -gA PROFILE_CHOICES=()

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

# Links a variant of a choice folder as selected.<ext>, replacing the
# previous selection.
#
# Args:
#   dir: The choice folder.
#   variant: The variant file name.
_link_variant() {
    local dir="$1"
    local variant="$2"

    local name="selected"
    if [[ "$variant" == *.* ]]; then
        name="selected.${variant##*.}"
    fi

    _clear_selection "$dir"
    ln -s "$variant" "$dir/$name"
}

# Links the variant of a choice set by the profile, or asks which one to use
# (the current one, or default, being the answer to Enter).
#
# Args:
#   dir: The choice folder.
choose_variant() {
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

    local variant

    # The variant set by the profile, when it names an existing one
    local wanted="${PROFILE_CHOICES[${dir#"$SETUP_DIR"/}]}"
    if [ -n "$wanted" ]; then
        for variant in "${variants[@]}"; do
            if [ "${variant%.*}" = "$wanted" ]; then
                _link_variant "$dir" "$variant"
                log_success "$description: $wanted (profile)"
                return 0
            fi
        done
        log_warn "$description: the profile asks for '$wanted', which does not exist."
    fi

    local current="${variants[0]}"
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

    _link_variant "$dir" "$answer"
    log_success "$description: ${answer%.*}"
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

# Prints the comment written above the function of a block.
#
# Args:
#   id: The block id.
block_doc() {
    awk -v fn="${BLOCK_FUNCTION[$1]}" '
        $0 ~ "^" fn "\\(\\)" { printf "%s", doc; exit }
        /^#/ { sub(/^# ?/, ""); doc = doc $0 "\n"; next }
        { doc = "" }
    ' "${BLOCK_SOURCE[$1]}"
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
