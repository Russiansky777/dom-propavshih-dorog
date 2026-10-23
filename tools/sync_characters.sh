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
    # a new sheet (a new character, Nina's mirror poses): import like the other sheets — lossy WebP 0.85, no mipmaps;
    # Godot fills in the rest of the .import on the next import
    for f in "$DST/$id"/*.png; do
      [[ -f "$f" && ! -f "$f.import" ]] || continue
      name="$(basename "$f")"
      cat >"$f.import" <<EOF
[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/characters/$id/$name"

[params]

compress/mode=1
compress/lossy_quality=0.85
mipmaps/generate=false
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=1
EOF
      echo "  $id/$name.import written"
    done
    # A k× sheet (sprites.json texture_scale, G56: Agata 2,25×): VRAM-compressed, high quality (BPTC/BC7, 1 byte per
    # pixel on the GPU). Lossy WebP decodes to 4 bytes per pixel — Agata's sheets would take ≈ 1,7 GB of video memory
    # with mipmaps (a browser tab loses its WebGL context); BC7 — ≈ 0,42 GB, the detail kept. Desktop and web alike.
    if python3 -c "import json,sys;sys.exit(0 if float(json.load(open(sys.argv[1])).get('texture_scale',1))>1 else 1)" "$DST/$id/sprites.json"; then
      for f in "$DST/$id"/*.png.import; do
        [[ -f "$f" ]] || continue
        sed -i 's/^compress\/mode=.*/compress\/mode=2/; s/^compress\/high_quality=.*/compress\/high_quality=true/; s/^mipmaps\/generate=.*/mipmaps\/generate=true/' "$f"
        grep -q '^compress/high_quality=' "$f" || sed -i 's/^compress\/mode=2/compress\/mode=2\ncompress\/high_quality=true/' "$f"
        grep -q '^mipmaps/generate=' "$f" || printf 'mipmaps/generate=true\n' >>"$f"
      done
      echo "  $id: texture_scale > 1 — sheets imported VRAM-compressed (BPTC)"
    fi
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
