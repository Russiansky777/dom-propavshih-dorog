#!/usr/bin/env bash
# H1 state frames from the real game under Xvfb (lights, puppet Tikhon, layers): <out>/H1_v2_<name>.png.
# Usage: tools/shots_h1.sh [out_dir] ["name|flags|agata_x,y|pointer_x,y" ...]   (see game/tests/shots_h1.gd)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/M1}"
shift || true
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
  -s res://tests/shots_h1.gd -- "$OUT" "$@" 2>&1 | tee "$BUILD_DIR/logs/shots_h1.log" | grep -E "H1 frame|ERROR|SCRIPT" || true
