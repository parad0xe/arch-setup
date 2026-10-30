#!/bin/bash
# Installs the Arch setup on a fresh machine and starts it: installs git when
# it is missing, downloads the setup binary of the latest release (or of
# SETUP_VERSION) for this architecture, checks its SHA-256, clones the
# repository into ~/.dotfiles (or SETUP_DIR) and runs setup with the
# arguments given.
#
#   curl -fsSL https://raw.githubusercontent.com/parad0xe/arch-setup/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/parad0xe/arch-setup/main/bootstrap.sh | bash -s -- profile parad0xe
#
# Environment: SETUP_DIR (the clone, default ~/.dotfiles), SETUP_BRANCH
# (default main), SETUP_VERSION (a release tag, default the latest),
# SETUP_BIN_DIR (where the binary goes, default ~/.local/bin) and SETUP_REPO
# (owner/name of the repository of modules to clone, default
# parad0xe/arch-setup; the binary always comes from parad0xe/arch-setup).

set -euo pipefail

BINARY_REPO="parad0xe/arch-setup"
BINARY_URL="https://github.com/$BINARY_REPO"
SETUP_REPO="${SETUP_REPO:-$BINARY_REPO}"
REPO_URL="https://github.com/$SETUP_REPO"
SETUP_DIR="${SETUP_DIR:-$HOME/.dotfiles}"
SETUP_BRANCH="${SETUP_BRANCH:-main}"
SETUP_VERSION="${SETUP_VERSION:-latest}"
SETUP_BIN_DIR="${SETUP_BIN_DIR:-$HOME/.local/bin}"

say() {
    printf '[i] %s\n' "$1"
}

fail() {
    printf '[!!] %s\n' "$1" >&2
    exit 1
}

# ==========================================
# THE MACHINE
# ==========================================

check_machine() {
    if [ "$(id -u)" -eq 0 ]; then
        fail "Run the bootstrap as your user, not root: the setup deploys the configs into your home and uses sudo for the system steps."
    fi
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64 | aarch64) ;;
        *) fail "Unsupported architecture $ARCH: the setup runs on x86_64 and aarch64." ;;
    esac
}

install_git() {
    if command -v git > /dev/null 2>&1; then
        return
    fi
    say "Installing git."
    if command -v pacman > /dev/null 2>&1; then
        sudo pacman -Syu --needed --noconfirm git
    elif command -v apt-get > /dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y --no-install-recommends git
    else
        fail "git is missing, and neither pacman nor apt-get is here to install it."
    fi
}

# ==========================================
# THE BINARY
# ==========================================

# Downloads the release for this architecture with its checksum, checks it,
# and installs it as SETUP_BIN_DIR/setup.
install_binary() {
    local name="setup-$ARCH" base tmp
    if [ "$SETUP_VERSION" = "latest" ]; then
        base="$BINARY_URL/releases/latest/download"
    else
        base="$BINARY_URL/releases/download/$SETUP_VERSION"
    fi
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    say "Downloading $name ($SETUP_VERSION)."
    curl -fsSL -o "$tmp/$name" "$base/$name" || fail "Could not download $base/$name"
    curl -fsSL -o "$tmp/$name.sha256" "$base/$name.sha256" || fail "Could not download $base/$name.sha256"
    (cd "$tmp" && sha256sum -c --quiet "$name.sha256") || fail "The checksum of $name does not match: download it again."
    mkdir -p "$SETUP_BIN_DIR"
    install -m 755 "$tmp/$name" "$SETUP_BIN_DIR/setup"
    rm -rf "$tmp"
    trap - EXIT
    say "Installed $SETUP_BIN_DIR/setup."
}

# ==========================================
# THE REPOSITORY
# ==========================================

clone_repository() {
    if [ -d "$SETUP_DIR/.git" ]; then
        say "Repository already in $SETUP_DIR: bringing it up to date."
        git -C "$SETUP_DIR" pull --ff-only --quiet || say "Could not fast-forward $SETUP_DIR: left as it is."
        return
    fi
    if [ -e "$SETUP_DIR" ]; then
        fail "$SETUP_DIR exists and is not a git repository: move it away, or set SETUP_DIR."
    fi
    say "Cloning $REPO_URL ($SETUP_BRANCH) into $SETUP_DIR."
    git clone --quiet --branch "$SETUP_BRANCH" "$REPO_URL.git" "$SETUP_DIR"
}

# ==========================================
# MAIN
# ==========================================

check_machine
install_git
install_binary
clone_repository
say "Starting the setup."
# Piped from curl, stdin is the pipe: the keyboard is the terminal
if [ -t 0 ] || ! { : < /dev/tty; } 2> /dev/null; then
    exec "$SETUP_BIN_DIR/setup" --repo "$SETUP_DIR" "$@"
fi
exec "$SETUP_BIN_DIR/setup" --repo "$SETUP_DIR" "$@" < /dev/tty
