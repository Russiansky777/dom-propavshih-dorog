#!/usr/bin/env bash
# Clean room frames from the real game under Xvfb (lights + ambient layer on): Docs/evidence/M1/real_<ROOM>.png.
# Usage: tools/shots_room.sh [out_dir] [ROOM[:x,y] ...]   (x,y — where Agata walks before the frame)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/M1}"
shift || true
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"  # Godot runs in game/: a relative path would land there
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
  -s res://tests/shots_room.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_room.log" | grep -E "room frame|ERROR|SCRIPT" || true
