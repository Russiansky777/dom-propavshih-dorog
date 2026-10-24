#!/usr/bin/env bash
# Frames of the optional stories Q02 «На карте вырос сад» and Q06 «Второй верстак» from the real game under Xvfb:
# the old map in the class and its close-up (the way by clicks, H47), Ilya's workshop and the second bench (drags, H48)
# step by step, both traces in the rooms and the epilogue frames → <out_dir>/q_<name>.png.
# Usage: tools/shots_quests.sh [out_dir] [name ...]   (names: game/tests/shots_quests.gd SHOTS)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$BUILD_DIR/shots/quests}"
shift || true
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 --audio-driver Dummy \
  -s res://tests/shots_quests.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_quests.log" | grep -E "quest frame|ERROR|SCRIPT" || true
