#!/bin/bash
# Shared by the bats files: a sandbox (temporary HOME, moved system files,
# fake system tools first in PATH), the library loader and small assertion
# helpers (bats-assert is not available).

bats_require_minimum_version 1.5.0

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ==========================================
# SANDBOX
# ==========================================

# Puts the test in a sandbox under BATS_TEST_TMPDIR: nothing it does reaches
# the real home, boot files or package manager. Output is made
# deterministic: no terminal, no colors, ASCII symbols, C locale.
sandbox_setup() {
    SANDBOX="$BATS_TEST_TMPDIR"
    export HOME="$SANDBOX/home"
    export XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state"
    export XDG_CACHE_HOME="$HOME/.cache"
    export GRUB_DEFAULT_FILE="$SANDBOX/etc/grub"
    export GRUB_CFG_FILE="$SANDBOX/boot/grub.cfg"
    export LOADER_ENTRIES_DIR="$SANDBOX/boot/entries"
    export MKINITCPIO_CONF="$SANDBOX/etc/mkinitcpio.conf"
    export FAKE_BIN="$SANDBOX/bin"
    export FAKE_LOG="$SANDBOX/fake.log"
    export FAKE_ARCH="x86_64"
    mkdir -p "$HOME" "$FAKE_BIN" "$SANDBOX/etc" "$SANDBOX/boot"
    : > "$FAKE_LOG"
    export PATH="$FAKE_BIN:$PATH"

    export SETUP_NO_TTY=1 NO_COLOR=1 TERM=dumb LC_ALL=C
    unset SETUP_DIR SETUP_ASCII SETUP_LOG_FILE SETUP_STEP_LOG SETUP_STEP_STATUS \
        UI_QUIET INPUT_NAME
    fake_tools
}

# Writes a fake tool: it logs its arguments to FAKE_LOG and exits with
# FAKE_<NAME>_STATUS, or the given default status.
#
# Args:
#   name: The tool name.
#   status: Its exit status when FAKE_<NAME>_STATUS is unset (default: 0).
make_fake() {
    local name="$1" var="FAKE_${1^^}_STATUS"
    var="${var//-/_}"
    cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
echo "$name \$*" >> "\$FAKE_LOG"
exit "\${$var:-${2:-0}}"
EOF
    chmod +x "$FAKE_BIN/$name"
}

# Writes the fake system tools. sudo runs its command itself (-v and -n
# answer FAKE_SUDO_STATUS), pacman -Qq fails for the packages listed in
# FAKE_PACMAN_MISSING, uname -m prints FAKE_ARCH and pgrep -x pacman answers
# FAKE_PGREP_PACMAN; the real uname and pgrep answer the other calls.
fake_tools() {
    local tool
    for tool in yay systemctl grub-mkconfig mkinitcpio timedatectl hwclock chsh curl ping; do
        make_fake "$tool"
    done
    make_fake systemd-detect-virt 1

    cat > "$FAKE_BIN/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >> "$FAKE_LOG"
case "$1" in
    -v | -n) exit "${FAKE_SUDO_STATUS:-0}" ;;
esac
exec "$@"
EOF

    cat > "$FAKE_BIN/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$FAKE_LOG"
if [ "$1" = "-Qq" ]; then
    case " ${FAKE_PACMAN_MISSING-} " in
        *" $2 "*) exit 1 ;;
    esac
    exit 0
fi
exit "${FAKE_PACMAN_STATUS:-0}"
EOF

    cat > "$FAKE_BIN/uname" <<'EOF'
#!/bin/bash
if [ "$1" = "-m" ]; then
    echo "${FAKE_ARCH:-x86_64}"
    exit 0
fi
PATH="${PATH#"$FAKE_BIN":}" exec uname "$@"
EOF

    cat > "$FAKE_BIN/pgrep" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "-x pacman" ]; then
    exit "${FAKE_PGREP_PACMAN:-1}"
fi
PATH="${PATH#"$FAKE_BIN":}" exec pgrep "$@"
EOF
    chmod +x "$FAKE_BIN/sudo" "$FAKE_BIN/pacman" "$FAKE_BIN/uname" "$FAKE_BIN/pgrep"
}

# ==========================================
# LIBRARY
# ==========================================

# Runs a command without the DEBUG trap of bats, which costs a fraction of a
# millisecond per command run: loading the library and the modules runs
# thousands. The trap comes back for the test itself.
untraced() {
    local saved
    saved=$(trap -p DEBUG)
    trap - DEBUG
    "$@"
    eval "$saved"
}

# The sandbox and the library of the real repository.
repo_setup() {
    sandbox_setup
    load_lib
}

# The sandbox and a repository holding the real library and a fixture
# module whose hooks print their inputs or fail. Sets FIXTURE.
fixture_setup() {
    sandbox_setup
    FIXTURE="$SANDBOX/fixture"
    mkdir -p "$FIXTURE/modules/demo"
    cp -R "$REPO_DIR/lib" "$FIXTURE/lib"
    cat > "$FIXTURE/modules/demo/hooks.sh" <<'EOF'
#!/bin/bash

# Prints its inputs.
greet() {
    log_info "Hello $INPUT_NAME"
    echo "variant: ${VARIANT_THEME-}"
}

# Fails in the middle: the line after false must not run.
failing() {
    log_info "before failure"
    false
    log_info "after failure"
}

_helper() { :; }
EOF
}

# Sources the library of a repository (the real one by default) the way
# lib/hook.sh does, without its strict mode: bats has its own.
#
# Args:
#   dir: The repository (default: the real one).
load_lib() {
    export SETUP_DIR="${1:-$REPO_DIR}"
    # shellcheck source=../lib/core.sh
    source "$SETUP_DIR/lib/core.sh"
    # shellcheck source=../lib/ui.sh
    source "$SETUP_DIR/lib/ui.sh"
    # shellcheck source=../lib/platform.sh
    source "$SETUP_DIR/lib/platform.sh"
    ui_init
}

# ==========================================
# ASSERTIONS
# ==========================================

# Fails, printing a message and the last output.
fail() {
    printf '%s\n--- output ---\n%s\n' "$1" "${output-}" >&2
    return 1
}

assert_equal() {
    [ "$1" = "$2" ] || fail "expected: '$2'
actual:   '$1'"
}

assert_output_contains() {
    [[ "$output" == *"$1"* ]] || fail "output lacks: $1"
}

assert_output_lacks() {
    [[ "$output" != *"$1"* ]] || fail "output has: $1"
}

assert_output_matches() {
    [[ "$output" =~ $1 ]] || fail "output does not match: $1"
}

# One line of the output matches the regex (anchors apply to the line).
assert_line_matches() {
    local line
    # shellcheck disable=SC2154  # lines: set by run
    for line in "${lines[@]}"; do
        if [[ "$line" =~ $1 ]]; then
            return 0
        fi
    done
    fail "no output line matches: $1"
}

assert_file_contains() {
    grep -qF -- "$2" "$1" || fail "$1 lacks: $2
--- file ---
$(cat "$1" 2>&1)"
}

assert_file_lacks() {
    ! grep -qF -- "$2" "$1" || fail "$1 has: $2
--- file ---
$(cat "$1")"
}

assert_fake_called() {
    assert_file_contains "$FAKE_LOG" "$1"
}

assert_fake_not_called() {
    assert_file_lacks "$FAKE_LOG" "$1"
}

assert_symlink_to() {
    [ -L "$1" ] || fail "$1 is not a symbolic link"
    assert_equal "$(readlink "$1")" "$2"
}

assert_regular_file() {
    [ -f "$1" ] && [ ! -L "$1" ] || fail "$1 is not a regular file"
}
