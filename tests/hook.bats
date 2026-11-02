#!/usr/bin/env bats
# lib/hook.sh: one hook run by setup, with the inputs in the environment,
# its messages, its failures and the refused arguments.

load test_helper

setup() {
    untraced fixture_setup
    HOOK="$FIXTURE/lib/hook.sh"
}

@test "hook.sh: runs the function with the inputs and variants, its messages on stdout" {
    run env UI_QUIET=1 INPUT_NAME=world VARIANT_THEME=dark bash "$HOOK" "$FIXTURE/modules/demo/hooks.sh" greet
    [ "$status" -eq 0 ]
    assert_output_contains "[i] Hello world"
    assert_output_contains "variant: dark"
}

@test "hook.sh: the last message goes to the status file of a background step" {
    run env UI_QUIET=1 INPUT_NAME=you SETUP_STEP_STATUS="$SANDBOX/status" bash "$HOOK" "$FIXTURE/modules/demo/hooks.sh" greet
    [ "$status" -eq 0 ]
    assert_equal "$(cat "$SANDBOX/status")" "Hello you"
}

@test "hook.sh: stops at the first failing command and reports it" {
    run env UI_QUIET=1 bash "$HOOK" "$FIXTURE/modules/demo/hooks.sh" failing
    [ "$status" -eq 1 ]
    assert_output_contains "before failure"
    assert_output_lacks "after failure"
    assert_output_contains "[error] Command failed (code 1): false"
    assert_output_contains "in failing() at "
    assert_output_contains "modules/demo/hooks.sh:"
}

@test "hook.sh: a missing script or function is refused" {
    run env UI_QUIET=1 bash "$HOOK" "$FIXTURE/modules/nothing/hooks.sh" greet
    [ "$status" -eq 2 ]
    assert_output_contains "No module script:"
    run env UI_QUIET=1 bash "$HOOK" "$FIXTURE/modules/demo/hooks.sh" nothing
    [ "$status" -eq 2 ]
    assert_output_contains "Unknown hook: nothing"
    run env UI_QUIET=1 bash "$HOOK" "$FIXTURE/modules/demo/hooks.sh"
    [ "$status" -eq 2 ]
    assert_output_contains "Usage: hook.sh <module script> <function>"
}
