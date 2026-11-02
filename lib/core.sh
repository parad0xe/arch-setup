#!/bin/bash
# Paths of the repository, exit hooks and strict mode, for lib/hook.sh and
# the hooks of the modules.

# The repository
export SETUP_DIR="${SETUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SETUP_LIB_DIR="$SETUP_DIR/lib"
SETUP_MODULES_DIR="$SETUP_DIR/modules"

# Functions run when the script exits, registered with on_exit.
SETUP_EXIT_HOOKS=()

# Registers a function to run when the script exits.
#
# Args:
#   function: The function name.
on_exit() {
    if [ "${#SETUP_EXIT_HOOKS[@]}" -eq 0 ]; then
        trap setup_run_exit_hooks EXIT
    fi
    SETUP_EXIT_HOOKS+=("$1")
}

# Runs the exit hooks, last registered first, whatever happens in them.
setup_run_exit_hooks() {
    set +e
    trap - ERR
    local i
    for ((i = ${#SETUP_EXIT_HOOKS[@]} - 1; i >= 0; i--)); do
        "${SETUP_EXIT_HOOKS[i]}" || true
    done
}

# Reports a command that failed under set -e: the command, where it ran and
# the call stack, on stderr (the log of the step).
setup_on_error() {
    local code=$? command="$BASH_COMMAND"
    trap - ERR
    set +e

    printf '\n[error] Command failed (code %d): %s\n' "$code" "$command" >&2
    # The last frame is the script itself, which bash also calls main
    local i
    for ((i = 0; i < ${#FUNCNAME[@]} - 2; i++)); do
        printf '    in %s() at %s:%s\n' "${FUNCNAME[i + 1]}" \
            "${BASH_SOURCE[i + 1]#"$SETUP_DIR"/}" "${BASH_LINENO[i]}" >&2
    done
    exit "$code"
}

# Stops at the first failing command, in the functions and subshells too,
# and reports it.
setup_strict_mode() {
    set -Ee
    trap setup_on_error ERR
}
