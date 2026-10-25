#!/usr/bin/env bash
# Web export (single-threaded template) → build/web/index.html
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

mkdir -p "$BUILD_DIR/web" "$BUILD_DIR/logs"
godot_import

echo "[godot] export: $GODOT --headless --path $GAME_DIR --export-release Web ../build/web/index.html"
set +e
"$GODOT" --headless --path "$GAME_DIR" --export-release Web ../build/web/index.html 2>&1 | tee "$BUILD_DIR/logs/export_web.log"
code=${PIPESTATUS[0]}
set -e
if [[ "$code" -ne 0 || ! -f "$BUILD_DIR/web/index.wasm" ]]; then
  echo "[godot] web export FAILED (exit $code); see $BUILD_DIR/logs/export_web.log" >&2
  exit 1
fi
python3 -I "$ROOT/tools/listen_page.py" --out "$BUILD_DIR/web/listen"   # I-T1: страница прослушивания дублей озвучки
echo "[godot] web export OK:"
ls -la "$BUILD_DIR/web"
du -sh "$BUILD_DIR/web"
