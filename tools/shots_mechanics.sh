#!/usr/bin/env bash
# Frames of the shared mechanics (Director's notes 23.10, F4–F9, F12, F14) from the real game under Xvfb:
# «Рассмотреть», mother's mirror with the clock up close and the watch, the timing bar, the knot, the hook,
# the crossing → Docs/evidence/M2/mech_<name>.png.
# Usage: tools/shots_mechanics.sh [out_dir] [name ...]   (names: game/tests/shots_mechanics.gd SHOTS)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/M2}"
shift || true
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 --audio-driver Dummy \
  -s res://tests/shots_mechanics.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_mechanics.log" | grep -E "mech frame|ERROR|SCRIPT" || true
