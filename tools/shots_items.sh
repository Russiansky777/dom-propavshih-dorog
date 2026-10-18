#!/usr/bin/env bash
# Evidence frames for items and choices (agent «предметы и выборы», 18.10): Docs/evidence/M1/items_*.png,
# rendered by the real game (Main.tscn, OpenGL under Xvfb) — Z1 counter corners, Z2 locked door and the key,
# H1 photo/cups before and after V01, O1 chalk on the desk and the V03 pencil mark. Not a test (needs a
# display); the checks are game/tests/test_items.gd and test_room_geometry.gd.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/M1}"
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
  -s res://tests/shots_items.gd -- "$OUT" 2>&1 | tee "$BUILD_DIR/logs/shots_items.log" | grep -E "items frame|ERROR|SCRIPT" || true
ls -1 "$OUT"/items_*.png
