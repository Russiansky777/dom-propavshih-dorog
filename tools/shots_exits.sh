#!/usr/bin/env bash
# Exit hints in every room, from the real game under Xvfb: Docs/evidence/M1/exits_<ROOM>{,_hover,_reveal}.png
# (marks idle / pointer on an exit / Space reveal). Usage: tools/shots_exits.sh [out_dir] [ROOM ...]
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
  -s res://tests/shots_exits.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_exits.log" | grep -E "^exit |^hover |room frame|ERROR|SCRIPT" || true
