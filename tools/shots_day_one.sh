#!/usr/bin/env bash
# Evidence frames for day one by the final scenario (block 1, 22.10): Docs/evidence/M1/day1/*.png rendered by the real
# game (Main.tscn, OpenGL under Xvfb) — H2 bundle / mirror / brace (art batch 2), O1 drawer close-up and the plan,
# the board line, H1 night by the stove. Not a test (needs a display); the checks are game/tests/test_day_one.gd.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"
OUT="${1:-$ROOT/Docs/evidence/M1/day1}"
mkdir -p "$OUT" "$BUILD_DIR/logs"
OUT="$(cd "$OUT" && pwd)"
"$ROOT/tools/sync_story_data.sh"
godot_import
xvfb-run -a -s "-screen 0 1920x1080x24" \
  "$GODOT" --path "$GAME_DIR" --display-driver x11 --rendering-driver opengl3 --resolution 1920x1080 \
  -s res://tests/shots_day_one.gd -- "$OUT" 2>&1 | tee "$BUILD_DIR/logs/shots_day_one.log" | grep -E "day1 frame|ERROR|SCRIPT" || true
# evidence in the repository as JPEG (≈ 10× smaller than PNG frames)
python3 -I - "$OUT" <<'PY'
import sys
from pathlib import Path
from PIL import Image
for p in sorted(Path(sys.argv[1]).glob("day1_*.png")):
    Image.open(p).convert("RGB").save(p.with_suffix(".jpg"), quality=88, optimize=True)
    p.unlink()
PY
ls -1 "$OUT"/day1_*.jpg
