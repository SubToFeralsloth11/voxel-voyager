#!/usr/bin/env bash
# Runs the headless test suite. Fails on any FAIL line or GDScript error.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"
RUNNER=()
if [ -x "$HOME/.agents/bin/heavy" ]; then RUNNER=("$HOME/.agents/bin/heavy" 180); fi
out="$("${RUNNER[@]}" "$GODOT" --headless --path . res://tests/run_tests.tscn 2>&1)"
code=$?
echo "$out" | grep -vE '^Godot Engine|^$|heavy: line'
if [ $code -ne 0 ] || echo "$out" | grep -qE 'SCRIPT ERROR|^FAIL|Parse Error'; then
	echo "TESTS FAILED"
	exit 1
fi
echo "$out" | grep -q 'checks, 0 failures' || { echo "TESTS DID NOT COMPLETE"; exit 1; }
echo "TESTS PASSED"
