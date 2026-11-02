#!/usr/bin/env bats
# lib/ui.sh: terminal detection, formatting, messages and prompts without a
# terminal, logs and the background status file.

load test_helper

setup() {
    untraced repo_setup
}

# ---------- detection ----------

@test "ui_init: ASCII symbols on the Linux console even with a UTF-8 locale" {
    export LC_ALL=C.UTF-8 TERM=linux
    ui_init
    assert_equal "$UI_UNICODE" 0
    assert_equal "$UI_OK $UI_FAIL $UI_DOT" "OK !! *"
}

@test "ui_init: SETUP_ASCII forces the ASCII symbols" {
    export LC_ALL=C.UTF-8 TERM=xterm SETUP_ASCII=1
    ui_init
    assert_equal "$UI_UNICODE" 0
    assert_equal "$UI_OK" "OK"
}

@test "ui_init: Unicode symbols with a UTF-8 locale on a real terminal" {
    export LC_ALL=C.UTF-8 TERM=xterm
    ui_init
    assert_equal "$UI_UNICODE" 1
    assert_equal "$UI_OK $UI_FAIL $UI_DOT" "✔ ✖ ·"
}

@test "ui_init: ASCII symbols without a UTF-8 locale" {
    export LC_ALL=C TERM=xterm
    ui_init
    assert_equal "$UI_UNICODE" 0
}

@test "ui_init: no colors with NO_COLOR, nor when stdout is not a terminal" {
    export NO_COLOR=1 TERM=xterm
    ui_init
    assert_equal "$UI_COLOR" 0
    assert_equal "$C_RESET$C_BOLD$C_DIM$C_RED$C_GREEN$C_YELLOW$C_BLUE$C_CYAN" ""

    unset NO_COLOR
    ui_init
    [ ! -t 1 ]
    assert_equal "$UI_COLOR" 0
    assert_equal "$C_BOLD" ""
}

@test "ui_init: no terminal with SETUP_NO_TTY, so no prompts" {
    assert_equal "$UI_TTY" 0
    ! ui_can_prompt
}

# ---------- formatting ----------

# ---------- messages ----------

@test "log_*: tagged lines on stdout" {
    run log_info "hello"
    assert_equal "$output" "[i] hello"
    run log_success "yes"
    assert_equal "$output" "[OK] yes"
    run log_warn "careful"
    assert_equal "$output" "[!] careful"
    run log_error "bad"
    assert_equal "$output" "[!!] bad"
}

@test "messages go to SETUP_LOG_FILE with a time, outside a step" {
    SETUP_LOG_FILE="$SANDBOX/setup.log"
    run log_info "logged line"
    assert_equal "$output" "[i] logged line"
    run ui_say "plain line"
    assert_equal "$output" "plain line"
    run cat "$SETUP_LOG_FILE"
    assert_line_matches '^[0-9]{2}:[0-9]{2}:[0-9]{2} \[i\] logged line$'
    assert_line_matches '^[0-9]{2}:[0-9]{2}:[0-9]{2} plain line$'
}

@test "ui_say logs the plain version of a colored line" {
    SETUP_LOG_FILE="$SANDBOX/setup.log"
    ui_say $'\033[1mbold\033[0m' "bold" > /dev/null
    assert_file_contains "$SETUP_LOG_FILE" " bold"
    assert_file_lacks "$SETUP_LOG_FILE" $'\033'
}

@test "in a step, the messages are logged with a terminal only (stdout is the log otherwise)" {
    SETUP_LOG_FILE="$SANDBOX/setup.log"
    SETUP_STEP_LOG="$SANDBOX/step.log"

    # Without a terminal the runner copies stdout to the step log
    run log_info "in a step"
    assert_equal "$output" "[i] in a step"
    [ ! -e "$SETUP_STEP_LOG" ]
    [ ! -e "$SETUP_LOG_FILE" ]

    # With one, the step log receives the line (_ui_log never touches the tty)
    UI_TTY=1 _ui_log "[i] from a terminal"
    assert_file_contains "$SETUP_STEP_LOG" "[i] from a terminal"
    [ ! -e "$SETUP_LOG_FILE" ]
}

@test "UI_QUIET: the message is printed and its first line written to the status file" {
    UI_QUIET=1
    SETUP_STEP_STATUS="$SANDBOX/status"
    SETUP_LOG_FILE="$SANDBOX/setup.log"
    run log_info $'working\nsecond line'
    assert_equal "$output" $'[i] working\nsecond line'
    log_info $'working\nsecond line' > /dev/null
    assert_equal "$(cat "$SETUP_STEP_STATUS")" "working"
    [ ! -e "$SETUP_LOG_FILE" ]

    # An error is not a status: the last message stays
    log_error "failed" > /dev/null
    assert_equal "$(cat "$SETUP_STEP_STATUS")" "working"
    log_success "finished" > /dev/null
    assert_equal "$(cat "$SETUP_STEP_STATUS")" "finished"
}

# ---------- prompts ----------

# ---------- background tasks ----------

