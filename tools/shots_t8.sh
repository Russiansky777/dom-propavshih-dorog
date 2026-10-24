#!/usr/bin/env bash
# T8 frames from the real game under Xvfb: start point + extra flags + room (game/tests/shots_t8.gd).
# Usage: tools/shots_t8.sh <out_dir> "name|start|ROOM[:x,y]|flag1,-flag2" ...
# NO_IMPORT=1 — skip sync and import (already done in this checkout).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="$1"; shift
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
if [[ -z "${NO_IMPORT:-}" ]]; then
  "$ROOT/tools/sync_story_data.sh" >/dev/null
  godot_import
fi
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
  -s res://tests/shots_t8.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_t8.log" | grep -E "t8 frame|ERROR|SCRIPT" || true
