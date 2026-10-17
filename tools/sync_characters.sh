#!/usr/bin/env bash
# Copies the character sheets Codex/the pipeline delivers in assets/characters/<id>/ into the Godot
# project (game/assets/characters/<id>/): sheets (*.png except the Meshy preview views) and sprites.json.
# Claude Code never edits assets/; the game only reads its own copy.
#   tools/sync_characters.sh [id ...]        (default: every folder in assets/characters)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/characters"
DST="$ROOT/game/assets/characters"
ids=("$@")
if [[ ${#ids[@]} -eq 0 ]]; then
  for d in "$SRC"/*/; do ids+=("$(basename "$d")"); done
fi
for id in "${ids[@]}"; do
  [[ -d "$SRC/$id" ]] || { echo "sync_characters: no assets/characters/$id" >&2; exit 1; }
  mkdir -p "$DST/$id"
  changed=0
  for f in "$SRC/$id"/*.png "$SRC/$id"/sprites.json; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    [[ "$name" == view_*.png ]] && continue
    if ! cmp -s "$f" "$DST/$id/$name"; then
      cp "$f" "$DST/$id/$name"
      changed=$((changed + 1))
      echo "  $id/$name updated"
    fi
  done
  echo "sync_characters: $id — $changed file(s) copied"
done
