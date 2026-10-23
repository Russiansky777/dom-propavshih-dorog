#!/usr/bin/env bash
# Copies the character sheets Codex/the pipeline delivers in assets/characters/<id>/ into the Godot
# project (game/assets/characters/<id>/): sheets of sprites.json (packed into atlases) and sprites.json.
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
  # Sheets: packed into an atlas for the game (tools/pack_sheets.py: each frame cropped to the figure — the web
  # build carries about a third of the grid's pixels; ActorSheet rebuilds the full frame with AtlasTexture.margin).
  # A sheet byte-identical to another action's (a clip mix-up in the pipeline) is not copied. SYNC_GRID=1 — grids.
  if [[ -f "$SRC/$id/sprites.json" ]]; then
    python3 -I "$ROOT/tools/pack_sheets.py" --src "$SRC/$id" --dst "$DST/$id" ${SYNC_GRID:+--grid}
  else
    # no sheet manifest (one-picture rig, Tikhon): pictures as they are
    for f in "$SRC/$id"/*.png; do
      [[ -f "$f" ]] || continue
      name="$(basename "$f")"
      [[ "$name" == view_*.png ]] && continue
      if ! cmp -s "$f" "$DST/$id/$name"; then cp "$f" "$DST/$id/$name"; changed=$((changed + 1)); echo "  $id/$name updated"; fi
    done
  fi
  # Real 3D (Agata, actor data render "3d"): only the game GLB (<id>_rt.glb: decimated mesh, all clips);
  # the Meshy originals (<id>.glb, <id>_extra_r*.glb, ~40 MB each) stay in assets/ as sources.
  if [[ -f "$SRC/$id/rt3d/${id}_rt.glb" ]]; then
    mkdir -p "$DST/$id/rt3d"
    if ! cmp -s "$SRC/$id/rt3d/${id}_rt.glb" "$DST/$id/rt3d/${id}_rt.glb"; then
      cp "$SRC/$id/rt3d/${id}_rt.glb" "$DST/$id/rt3d/${id}_rt.glb"
      changed=$((changed + 1))
      echo "  $id/rt3d/${id}_rt.glb updated"
    fi
  fi
  echo "sync_characters: $id — $changed file(s) copied"
done
