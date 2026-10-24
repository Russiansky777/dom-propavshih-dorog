#!/usr/bin/env bash
# Batch H, T2: frames from the real game under Xvfb → Docs/evidence/H/T2_*.jpg (game/tests/shots_h_t2.gd).
# Usage: tools/shots_h_t2.sh [name ...]   (names: H17_bed_early H17_bed_late H12_scarf_over_shelf H12_shelf_on_bench
#        H15_cup_touch H29_lever H24_door_open H28_pavel_door; none — all)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="$ROOT/Docs/evidence/H"
mkdir -p "$OUT" "$BUILD_DIR/logs"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 --audio-driver Dummy \
  -s res://tests/shots_h_t2.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_h_t2.log" | grep -E "^shot|SCRIPT ERROR" || true
