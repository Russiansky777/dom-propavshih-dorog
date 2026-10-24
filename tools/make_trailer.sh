#!/usr/bin/env bash
# TR1: renders a trailer plan (data/trailer/<id>.json) shot by shot with Godot's Movie Maker and cuts it with ffmpeg.
#   tools/make_trailer.sh [plan_id] [shot_id …]   — default test_7s, every shot
# Each shot: res://scenes/trailer/Trailer.tscn in a virtual X display (xvfb-run, software Mesa: the runners have no
# GPU) → build/trailer/<plan>/<shot>/f########.png + f.wav at the plan's fps and render size (3840×2160).
# Then tools/trailer_assemble.py: dissolves / fades, the title, music, ambience, loudness → build/trailer/<plan>.mp4.
# Needs xvfb, ffmpeg (sudo apt-get install -y xvfb mesa-utils ffmpeg).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

PLAN="${1:-test_7s}"
shift || true
"$ROOT/tools/sync_story_data.sh"
PLAN_JSON="$ROOT/data/trailer/$PLAN.json"
read -r FPS W H SHOTS < <(python3 -I -c '
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
w, h = p.get("render_size", [3840, 2160])
print(p.get("fps", 60), w, h, ",".join(s["id"] for s in p["shots"]))' "$PLAN_JSON")
if [[ $# -gt 0 ]]; then SHOTS="$(IFS=,; echo "$*")"; fi

[[ -d "$GAME_DIR/.godot/imported" ]] || godot_import
OUT="$BUILD_DIR/trailer/$PLAN"
mkdir -p "$OUT" "$BUILD_DIR/logs"
IFS=',' read -ra LIST <<< "$SHOTS"
# Movie Maker records at the window size; `--resolution` does not raise it past the project's 1920×1080 here, the
# window size override does (Godot docs, «Creating movies»: render above the screen size). A temporary override.cfg
# next to project.godot, removed on exit.
printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$W" "$H" > "$GAME_DIR/override.cfg"
trap 'rm -f "$GAME_DIR/override.cfg"' EXIT
for shot in "${LIST[@]}"; do
  rm -rf "${OUT:?}/$shot"
  mkdir -p "$OUT/$shot"
  echo "[trailer] $PLAN/$shot → $OUT/$shot (${W}x${H}, ${FPS} fps)"
  start=$(date +%s)
  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 ${W}x${H}x24" \
    "$GODOT" --path "$GAME_DIR" --rendering-driver opengl3 --disable-vsync \
      --write-movie "$OUT/$shot/f.png" --fixed-fps "$FPS" \
      res://scenes/trailer/Trailer.tscn -- "--trailer=res://data/trailer/$PLAN.json" "--shot=$shot" \
      >"$BUILD_DIR/logs/trailer_${PLAN}_${shot}.log" 2>&1 || {
        echo "[trailer] $shot: Godot exited with $? (log: build/logs/trailer_${PLAN}_${shot}.log)" >&2
        tail -20 "$BUILD_DIR/logs/trailer_${PLAN}_${shot}.log" >&2
        exit 1
      }
  n=$(find "$OUT/$shot" -name 'f*.png' | wc -l)
  echo "[trailer] $shot: $n frames in $(( $(date +%s) - start )) s"
done
[[ "${NO_ASSEMBLE:-}" == 1 ]] || python3 -I "$ROOT/tools/trailer_assemble.py" "$PLAN"
