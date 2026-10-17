#!/usr/bin/env bash
# Evidence frames of NPC conversations (Docs/evidence/M1/talk_<ROOM>_<npc>.png) from the real game under
# Xvfb: Agata walks to the NPC's stand and talks; the frame is taken on the first dialogue line, so it shows
# whether both figures stay visible. Usage: tools/shots_dialogue.sh [out_dir] [ROOM:hotspot ...]
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
  -s res://tests/shots_dialogue.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_dialogue.log" | grep -E "dialogue frame|ERROR|SCRIPT" || true
