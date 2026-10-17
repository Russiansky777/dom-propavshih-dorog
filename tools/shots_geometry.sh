#!/usr/bin/env bash
# Evidence frames for room geometry: Docs/evidence/M1/geometry_<LOC>.png, rendered by the real game
# (Main.tscn, OpenGL under Xvfb). In every room Agata walks from the default spawn towards a point inside
# an obstacle or water (first no_walk_samples entry) and stops at the floor edge; the frame carries a thin
# overlay of the floor outline. Not a test (needs a display); the geometry test is test_room_geometry.gd.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/M1}"
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"  # Godot runs in game/: a relative path would land there
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
  -s res://tests/shots_geometry.gd -- "$OUT" 2>&1 | tee "$BUILD_DIR/logs/shots_geometry.log" | grep -E "geometry frame|ERROR|SCRIPT" || true
ls -1 "$OUT"/geometry_*.png
