#!/usr/bin/env bash
# Minimal bash 3.2 portable test helpers for claude-alloy.
# No mapfile, no associative arrays, no local -n — runs on stock macOS bash.

TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    _expected=$1
    _actual=$2
    _name=$3
    if [ "$_expected" = "$_actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS: %s\n' "$_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$_name" "$_expected" "$_actual"
    fi
}

assert_exit() {
    _expected=$1
    _actual=$2
    _name=$3
    if [ "$_expected" = "$_actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf 'PASS: %s (exit=%s)\n' "$_name" "$_actual"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'FAIL: %s\n  expected exit: %s\n  actual exit:   %s\n' "$_name" "$_expected" "$_actual"
    fi
}

strip_ansi() {
    # Use bash ANSI-C quoting to substitute \x1b → real ESC byte BEFORE sed
    # sees the pattern. `\x1b` as a regex token is a GNU-sed extension; BSD
    # sed (macOS) treats it as a literal backslash + x + 1 + b. ANSI-C quoting
    # sidesteps that by embedding a real ESC byte in the script so both seds
    # behave identically. The `\\[` is a literal `[` to sed.
    sed $'s/\x1b\\[[0-9;]*m//g'
}

done_testing() {
    printf '\n%s passed, %s failed\n' "$TESTS_PASSED" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ] || exit 1
    exit 0
}
