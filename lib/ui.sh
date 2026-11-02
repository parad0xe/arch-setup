#!/bin/bash
# Messages of the hooks: tagged, colored when the terminal shows colors, and
# written to the log of the step (SETUP_STEP_LOG) when stdout is not the log
# itself. setup shows and keeps them.

UI_TTY=0        # /dev/tty is usable: a foreground (attended) step
UI_COLOR=0      # stdout is a terminal showing colors
UI_UNICODE=0    # the terminal shows the Unicode symbols
UI_QUIET="${UI_QUIET:-0}"   # 1 in a background step, whose stdout is its log
SETUP_LOG_FILE="${SETUP_LOG_FILE:-}"
SETUP_STEP_LOG="${SETUP_STEP_LOG:-}"
SETUP_STEP_STATUS="${SETUP_STEP_STATUS:-}"  # the last message of a background step

C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
UI_OK="OK" UI_FAIL="!!" UI_DOT="*"

# Detects what the terminal can show: colors (not with NO_COLOR nor a dumb
# terminal) and the Unicode symbols (a UTF-8 locale, outside the Linux
# console, whose fonts lack them).
ui_init() {
    UI_TTY=0
    if [ -z "${SETUP_NO_TTY-}" ] && { : < /dev/tty; } 2> /dev/null && { : > /dev/tty; } 2> /dev/null; then
        UI_TTY=1
    fi

    UI_COLOR=0
    local colors
    colors=$(tput colors 2> /dev/null) || colors=0
    if [ -t 1 ] && [ -z "${NO_COLOR-}" ] && [ "${TERM:-dumb}" != dumb ] && [ "${colors:-0}" -ge 8 ] 2> /dev/null; then
        UI_COLOR=1
    fi
    if [ "$UI_COLOR" = 1 ]; then
        C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
        C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m' C_CYAN=$'\033[36m'
    else
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
    fi

    UI_UNICODE=0
    if [ -z "${SETUP_ASCII-}" ] && [ "${TERM-}" != linux ] && _ui_utf8_locale; then
        UI_UNICODE=1
    fi
    if [ "$UI_UNICODE" = 1 ]; then
        UI_OK="✔" UI_FAIL="✖" UI_DOT="·"
    else
        UI_OK="OK" UI_FAIL="!!" UI_DOT="*"
    fi
}

# Returns success when the locale encodes text in UTF-8.
_ui_utf8_locale() {
    local charmap
    charmap=$(locale charmap 2> /dev/null) || charmap="${LC_ALL:-${LC_CTYPE:-${LANG-}}}"
    [[ "${charmap^^}" == *UTF-8* || "${charmap^^}" == *UTF8* ]]
}

# ==========================================
# MESSAGES
# ==========================================

# Appends a line to the log of the step, or to SETUP_LOG_FILE outside a
# step. In a step whose stdout already goes to its log (a background step,
# or a foreground one without a terminal), nothing to do.
#
# Args:
#   text: The line, without color codes.
_ui_log() {
    local file="${SETUP_STEP_LOG:-$SETUP_LOG_FILE}"
    if [ -n "$SETUP_STEP_LOG" ] && { [ "$UI_QUIET" = 1 ] || [ "$UI_TTY" != 1 ]; }; then
        return 0
    fi
    if [ -n "$file" ]; then
        printf '%s %s\n' "$(date +%H:%M:%S)" "$1" >> "$file"
    fi
}

# Prints a line for the user: on stdout, or on the terminal in a foreground
# step, whose stdout is copied to its log. In a background step, stdout is
# the log.
#
# Args:
#   text: The line, with color codes.
_ui_print() {
    if [ "$UI_QUIET" != 1 ] && [ -n "$SETUP_STEP_LOG" ] && [ "$UI_TTY" = 1 ]; then
        printf '%s\n' "$1" > /dev/tty
    else
        printf '%s\n' "$1"
    fi
}

# Prints a message, tagged and colored, and logs it. In a background step it
# only goes to the log, and becomes the message shown next to the spinner.
#
# Args:
#   kind: info, success, warn or error.
#   msg: The message (several lines allowed).
_ui_message() {
    local kind="$1" msg="$2" tag color
    case "$kind" in
        info)    tag="[i]"; color="$C_BLUE" ;;
        success) tag="[$UI_OK]"; color="$C_GREEN" ;;
        warn)    tag="[!]"; color="$C_YELLOW" ;;
        error)   tag="[$UI_FAIL]"; color="$C_RED" ;;
    esac

    if [ "$UI_QUIET" = 1 ]; then
        printf '%s %s\n' "$tag" "$msg"
        if [ -n "$SETUP_STEP_STATUS" ] && [ "$kind" != error ]; then
            printf '%s\n' "${msg%%$'\n'*}" > "$SETUP_STEP_STATUS"
        fi
        return 0
    fi

    _ui_log "$tag $msg"
    _ui_print "${C_BOLD}${color}${tag}${C_RESET} ${msg}"
}

# Prints an informational message.
#
# Args:
#   msg: The message.
log_info() {
    _ui_message info "$1"
}

# Prints a success message.
#
# Args:
#   msg: The message.
log_success() {
    _ui_message success "$1"
}

# Prints a warning.
#
# Args:
#   msg: The message.
log_warn() {
    _ui_message warn "$1"
}

# Prints an error message.
#
# Args:
#   msg: The message.
log_error() {
    _ui_message error "$1"
}

# Prints a plain line (no tag) and logs it.
#
# Args:
#   text: The line, with color codes.
#   plain: The same line without them (default: the line).
ui_say() {
    _ui_log "${2:-$1}"
    _ui_print "$1"
}
