#!/usr/bin/env bash
# Run the whole test suite headless. Usage: tests/run.sh [file-name-filter]
# Fails (exit 1) on a failed check, on any "SCRIPT ERROR" (a test that crashed
# mid-way), or on a timeout. Refreshes Godot's class cache first.
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

"$GODOT" --headless --import >/dev/null 2>&1

timeout "${TEST_TIMEOUT:-120}" "$GODOT" --headless -s tests/run_tests.gd -- "${1:-}" >"$LOG" 2>&1
STATUS=$?

grep -v -i -E "gtk|zenity|^$" "$LOG"

if [ "$STATUS" -eq 124 ]; then
	echo "TIMEOUT: tests did not finish" >&2
	exit 1
fi
if grep -q -E "SCRIPT ERROR|Parse Error|Compile Error" "$LOG"; then
	echo "FAILED: script errors in output" >&2
	exit 1
fi
exit "$STATUS"
