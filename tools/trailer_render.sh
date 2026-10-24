#!/usr/bin/env bash
# TR2: renders a trailer plan file shot by shot (Godot Movie Maker) and cuts it (tools/trailer_assemble.py).
#   tools/trailer_render.sh <plan.json> [shot_id …]
# Env: RENDER_SIZE=WxH and FPS=n override the plan (previews: RENDER_SIZE=960x540 FPS=15); NO_ASSEMBLE=1 renders
# frames only; SKIP_EXISTING=1 keeps shots already rendered (a shot is done when build/trailer/<id>/<shot>/.done exists).
# A shot's own `render_size` (phrases on black need no 4K) beats the plan's. Output: build/trailer/<id>.mp4.
# Needs xvfb, ffmpeg (sudo apt-get install -y xvfb mesa-utils ffmpeg).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

PLAN_FILE="$(realpath "${1:?usage: tools/trailer_render.sh <plan.json> [shot_id …]}")"
shift || true
"$ROOT/tools/sync_story_data.sh"
# The game reads the plan as res://data/trailer/<name>.json: a plan from elsewhere is copied there for the run.
PLAN="$(basename "$PLAN_FILE" .json)"
mkdir -p "$GAME_DIR/data/trailer"
[[ "$PLAN_FILE" -ef "$GAME_DIR/data/trailer/$PLAN.json" ]] || cp "$PLAN_FILE" "$GAME_DIR/data/trailer/$PLAN.json"
LIST_JSON="$(python3 -I - "$PLAN_FILE" "${RENDER_SIZE:-}" "${FPS:-}" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
size = [int(v) for v in sys.argv[2].split("x")] if sys.argv[2] else p.get("render_size", [3840, 2160])
fps = int(sys.argv[3]) if sys.argv[3] else p.get("fps", 60)
def sz(s):
    return size if sys.argv[2] else (s.get("render_size") or size)
print(fps, *[f'{s["id"]}:{sz(s)[0]}x{sz(s)[1]}' for s in p["shots"]])
PY
)"
read -ra ENTRIES <<< "$LIST_JSON"; FPS_USE="${ENTRIES[0]}"; ENTRIES=("${ENTRIES[@]:1}")

[[ -d "$GAME_DIR/.godot/imported" ]] || godot_import
OUT="$BUILD_DIR/trailer/$PLAN"
mkdir -p "$OUT" "$BUILD_DIR/logs"
trap 'rm -f "$GAME_DIR/override.cfg"' EXIT
for entry in "${ENTRIES[@]}"; do
  shot="${entry%%:*}"; size="${entry##*:}"; W="${size%x*}"; H="${size#*x}"
  if [[ $# -gt 0 ]]; then case " $* " in *" $shot "*) ;; *) continue ;; esac; fi
  if [[ "${SKIP_EXISTING:-}" == 1 && -f "$OUT/$shot/.done" ]]; then echo "[trailer] $shot: kept"; continue; fi
  # Movie Maker records at the window size; the window size override (not --resolution) lifts it above 1920×1080.
  printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$W" "$H" > "$GAME_DIR/override.cfg"
  rm -rf "${OUT:?}/$shot"; mkdir -p "$OUT/$shot"
  echo "[trailer] $PLAN/$shot (${W}x${H}, ${FPS_USE} fps)"
  start=$(date +%s)
  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 ${W}x${H}x24" \
    "$GODOT" --path "$GAME_DIR" --rendering-driver opengl3 --disable-vsync \
      --write-movie "$OUT/$shot/f.png" --fixed-fps "$FPS_USE" \
      res://scenes/trailer/Trailer.tscn -- "--trailer=res://data/trailer/$PLAN.json" "--shot=$shot" \
      >"$BUILD_DIR/logs/trailer_${PLAN}_${shot}.log" 2>&1 || {
        echo "[trailer] $shot: Godot exited with $? (log: build/logs/trailer_${PLAN}_${shot}.log)" >&2
        tail -20 "$BUILD_DIR/logs/trailer_${PLAN}_${shot}.log" >&2
        exit 1
      }
  touch "$OUT/$shot/.done"
  echo "[trailer] $shot: $(find "$OUT/$shot" -name 'f*.png' | wc -l) frames in $(( $(date +%s) - start )) s"
done
[[ "${NO_ASSEMBLE:-}" == 1 ]] || FPS="$FPS_USE" python3 -I "$ROOT/tools/trailer_assemble.py" "$PLAN_FILE"
