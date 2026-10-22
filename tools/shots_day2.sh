#!/usr/bin/env bash
# Frames of day two from the real game under Xvfb: rooms M1–M4, R2, R3, evening Z3/R1 and the close-ups
# (office mirror, hook, sluice, mother's mirror, plate, lantern, photo) → Docs/evidence/M2/day2_<name>.png.
# Usage: tools/shots_day2.sh [out_dir] [name ...]   (names: game/tests/shots_day2.gd SHOTS)
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
  -s res://tests/shots_day2.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_day2.log" | grep -E "day2 frame|ERROR|SCRIPT" || true
