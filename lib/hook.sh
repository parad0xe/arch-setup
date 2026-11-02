#!/bin/bash
# Runs the hook of a unit for setup: a function of the module's script
# (modules/<module>/hooks.sh of the public or the private repository), with the
# helpers of lib/ui.sh and lib/platform.sh. The step stops at its first
# failing command and reports it on stderr.
#
# Usage: lib/hook.sh <module script> <function>
#
# Environment, set by setup (see docs/manifest.md):
#   SETUP_MODULE_ROOT   The repository declaring the module.
#   HOST_*              The platform (HOST_DISTRO, HOST_ARCH, HOST_GPU...).
#   INPUT_<ID>          The answer to each input of the unit.
#   VARIANT_<ID>        The option chosen for each variant of the unit.
#   SETUP_STEP_LOG      The log of the step, where the messages go.
#   SETUP_STEP_STATUS   A file receiving the last message, for the spinner.
#   UI_QUIET            1 when stdout is the log (a background step).
#
# Hooks never ask a question, and change nothing when run twice.

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
# shellcheck source=ui.sh
source "$SETUP_LIB_DIR/ui.sh"
# shellcheck source=platform.sh
source "$SETUP_LIB_DIR/platform.sh"
ui_init

script="${1-}" function="${2-}"
if [ -z "$script" ] || [ -z "$function" ]; then
    log_error "Usage: hook.sh <module script> <function>"
    exit 2
fi
if [ ! -f "$script" ]; then
    log_error "No module script: $script"
    exit 2
fi
# shellcheck source=/dev/null
source "$script"
if ! declare -F "$function" > /dev/null; then
    log_error "Unknown hook: $function is not a function of $script"
    exit 2
fi

setup_strict_mode
"$function"
