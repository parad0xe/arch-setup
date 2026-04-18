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

    wait "$pid"
    local status=$?

    tput sc
    tput cup $((lines - 1)) 0
    printf "\033[K"
    tput rc

    if [ $status -eq 0 ]; then
        printf "\033[1;32m✔\033[0m  %s\n\n" "$msg"
    else
        printf "\033[1;31m✖\033[0m  %s (See /tmp/setup.log)\n\n" "$msg"
        exit 1
    fi
}

# Prints an informational message to the standard output.
#
# Args:
#   msg: The message to display.
log_info() {
    printf "\r\033[K\033[1;34m[INFO]\033[0m %s\n" "$1" > /dev/tty
}

# Prints an error message to the standard output.
#
# Args:
#   msg: The error message to display.
log_error() {
    printf "\r\033[K\033[1;31m[ERROR]\033[0m %s\n" "$1" > /dev/tty
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

    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        log_info "Archiving existing configuration: $dest -> ${dest}.bak"
        mv "$dest" "${dest}.bak"
    elif [ -L "$dest" ]; then
        rm "$dest"
    fi

    log_info "Creating symbolic link: $src -> $dest"
    ln -s "$src" "$dest"
}

# Entry point for the core module.
setup() {
    init_ui
}
