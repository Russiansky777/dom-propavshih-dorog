#!/usr/bin/env bash
# Tests, three levels (exit code 0 == all PASS):
#   1. python3 tools/validate_story.py   — story data integrity
#      python3 tools/validate_rooms.py   — rooms JSON vs story (test (a) of M1)
#   2. godot --headless -s res://tests/run_tests.gd — GameState/RoomManager/navigation, bot walkthrough
#      godot --headless -s res://tests/test_room_geometry.gd — floor vs art in every room (samples)
# Output is also written to build/logs/tests.log
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

mkdir -p "$BUILD_DIR/logs"
: > "$BUILD_DIR/logs/tests.log"
code=0

echo "[data] validate_story.py" | tee -a "$BUILD_DIR/logs/tests.log"
python3 -I "$ROOT/tools/validate_story.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1
echo "[data] validate_rooms.py" | tee -a "$BUILD_DIR/logs/tests.log"
python3 -I "$ROOT/tools/validate_rooms.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1
python3 -I "$ROOT/tools/validate_lights.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # свет комнат: data/story/lights

"$ROOT/tools/sync_story_data.sh" | tee -a "$BUILD_DIR/logs/tests.log"
godot_import

echo "[godot] tests: $GODOT --headless --path $GAME_DIR -s res://tests/run_tests.gd"
set +e
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/run_tests.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log"
gcode=${PIPESTATUS[0]}
set -e
[[ "$gcode" -ne 0 ]] && code=1
echo "[godot] tests exit code: $gcode"

# Room geometry against the art: obstacles/water not walkable, floor connected (data: *_samples).
echo "[godot] geometry: $GODOT --headless --path $GAME_DIR -s res://tests/test_room_geometry.gd" | tee -a "$BUILD_DIR/logs/tests.log"
set +e
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_room_geometry.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log"
geo_code=${PIPESTATUS[0]}
set -e
[[ "$geo_code" -ne 0 ]] && code=1
echo "[godot] geometry exit code: $geo_code"
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_lighting.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # свет, огонь, тени актёров
echo "[tests] overall exit code: $code"
exit "$code"
