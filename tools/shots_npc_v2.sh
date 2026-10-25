#!/usr/bin/env bash
# I-T4: villagers v2 in their rooms from the real game under Xvfb — stands / listens / talks (two talk frames: mouth)
# → Docs/evidence/i_t4/npc_v2_<id>.png.
# Usage: tools/shots_npc_v2.sh [out_dir] [id ...]   (default: all eight)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/i_t4}"
shift || true
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 --audio-driver Dummy \
  -s res://tests/shots_npc_v2.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_npc_v2.log" | grep -E "npc_v2 shot|ERROR|SCRIPT" || true
