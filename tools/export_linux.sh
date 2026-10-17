#!/usr/bin/env bash
# Linux x86_64 export → build/linux/game.x86_64 (+ game.pck)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

mkdir -p "$BUILD_DIR/linux" "$BUILD_DIR/logs"
godot_import

echo "[godot] export: $GODOT --headless --path $GAME_DIR --export-release Linux ../build/linux/game.x86_64"
set +e
"$GODOT" --headless --path "$GAME_DIR" --export-release Linux ../build/linux/game.x86_64 2>&1 | tee "$BUILD_DIR/logs/export_linux.log"
code=${PIPESTATUS[0]}
set -e
if [[ "$code" -ne 0 || ! -f "$BUILD_DIR/linux/game.x86_64" ]]; then
  echo "[godot] linux export FAILED (exit $code); see $BUILD_DIR/logs/export_linux.log" >&2
  exit 1
fi
echo "[godot] linux export OK:"
ls -la "$BUILD_DIR/linux"
du -sh "$BUILD_DIR/linux"
