#!/usr/bin/env bash
# Headless Godot tests: tools/run_tests.sh  (exit code 0 == all PASS)
# Output is also written to build/logs/tests.log
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

mkdir -p "$BUILD_DIR/logs"
godot_import

echo "[godot] tests: $GODOT --headless --path $GAME_DIR -s res://tests/run_tests.gd"
set +e
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/run_tests.gd 2>&1 | tee "$BUILD_DIR/logs/tests.log"
code=${PIPESTATUS[0]}
set -e
echo "[godot] tests exit code: $code"
exit "$code"
