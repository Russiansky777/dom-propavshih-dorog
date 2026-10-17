#!/usr/bin/env bash
# Copies data/story/ into game/data/story/ (Godot reads res://data/story). Symlinks are avoided on
# purpose: git on Windows would check them out as text files. Run before tests/exports (scripts do).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/data/story"
DST="$ROOT/game/data/story"
mkdir -p "$DST"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --include='*/' --include='*.json' --exclude='*' "$SRC/" "$DST/"
else
  rm -rf "$DST" && mkdir -p "$DST" && (cd "$SRC" && find . -name '*.json' -exec cp --parents {} "$DST/" \;)
fi
# Godot should not import JSON as resources; .gdignore is NOT used (it would hide the files from export).
echo "[data] synced $(find "$DST" -name '*.json' | wc -l) json files → game/data/story"
