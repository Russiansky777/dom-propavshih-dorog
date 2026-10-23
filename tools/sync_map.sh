#!/usr/bin/env bash
# Copies the plan pictures the pipeline delivers in assets/incoming/map/<name>.png into the Godot
# project (game/assets/ui/map/<name>.png). Claude Code never edits assets/; the game reads its copy.
# Contact sheets/previews (_*.png) are skipped. The import is lossy WebP q0.9 (a painted plan, shown
# at most ~1760 px wide): ≈10× smaller in the web build than lossless, no visible difference.
#   tools/sync_map.sh
# Labels, dots and «Вы здесь» are not in the picture: data/story/map_zarechye.json + zarechye_map.gd.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/incoming/map"
DST="$ROOT/game/assets/ui/map"
mkdir -p "$DST"
changed=0
n=0
for f in "$SRC"/*.png "$ROOT"/assets/incoming/zarechye_plan_*.png; do   # + слои плана партии 9 (G2: zarechye_plan_overlay)
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  [[ "$name" == _* ]] && continue
  n=$((n + 1))
  if ! cmp -s "$f" "$DST/$name"; then
    cp "$f" "$DST/$name"
    chmod 644 "$DST/$name"
    changed=$((changed + 1))
    echo "  ui/map/$name updated"
  fi
  if [[ ! -f "$DST/$name.import" ]]; then
    cat > "$DST/$name.import" <<EOF
[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/ui/map/$name"

[params]

compress/mode=1
compress/lossy_quality=0.9
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
detect_3d/compress_to=1
EOF
  fi
done
echo "sync_map: $n picture(s), $changed copied → game/assets/ui/map"
