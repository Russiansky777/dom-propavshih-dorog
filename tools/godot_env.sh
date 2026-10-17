#!/usr/bin/env bash
# Shared helper: locate the Godot 4.7.2 binary. Sourced by run_tests.sh / export_*.sh.
# Override with GODOT=/path/to/godot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$ROOT/game"
BUILD_DIR="$ROOT/build"

if [[ -z "${GODOT:-}" ]]; then
  for candidate in \
      "$HOME/tools-cache/Godot_v4.7.2-stable_linux.x86_64" \
      "/home/claude/tools-cache/Godot_v4.7.2-stable_linux.x86_64" \
      "$(command -v godot4 || true)" \
      "$(command -v godot || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      GODOT="$candidate"
      break
    fi
  done
fi

if [[ -z "${GODOT:-}" || ! -x "$GODOT" ]]; then
  echo "Godot binary not found. Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64" >&2
  exit 2
fi

godot_import() {
  # One-off resource import (textures, class cache). Required before -s scripts and exports.
  local log="$BUILD_DIR/logs/import.log"
  mkdir -p "$BUILD_DIR/logs"
  echo "[godot] import: $GODOT --headless --path $GAME_DIR --import"
  "$GODOT" --headless --path "$GAME_DIR" --import >"$log" 2>&1 || {
    echo "[godot] import exited with $? (see $log)" >&2
  }
}

export ROOT GAME_DIR BUILD_DIR GODOT
