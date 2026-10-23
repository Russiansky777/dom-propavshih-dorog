#!/usr/bin/env bash
# Copies item icons the pipeline delivers in assets/icons/<item_id>.png into the Godot project
# (game/assets/icons/<item_id>.png), trimmed to the visible object and scaled down to slot size.
# Claude Code never edits assets/; the game only reads its own copy. The bag (game_ui.gd) picks an
# icon up by name (res://assets/icons/<item_id>.png) — a new icon needs no code change.
#   tools/sync_icons.sh [item_id ...]        (default: every assets/icons/*.png except _contact*)
#   tools/sync_icons.sh item_id=assets/incoming/<file>.png   — an icon delivered under another name (batch 9:
#                                            key_sluice=assets/incoming/icon_sluice_lever.png, G20 «рычаг затвора»)
# Size: ICON_SIZE (default 192 px square) — a slot draws ~56 px at 1920x1080, the "fly into the bag"
# animation starts at ~112 px; 192 keeps both crisp on a 2x screen, mipmaps do the rest.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/icons"
DST="$ROOT/game/assets/icons"
SIZE="${ICON_SIZE:-192}"
mkdir -p "$DST"

ids=("$@")
if [[ ${#ids[@]} -eq 0 ]]; then
  for f in "$SRC"/*.png; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .png)"
    [[ "$name" == _* ]] && continue   # contact sheets / previews are not game icons
    ids+=("$name")
  done
fi

changed=0
for arg in "${ids[@]}"; do
  id="${arg%%=*}"
  if [[ "$arg" == *=* ]]; then src="$ROOT/${arg#*=}"; else src="$SRC/$id.png"; fi
  [[ -f "$src" ]] || { echo "sync_icons: no $src" >&2; exit 1; }
  dst="$DST/$id.png"
  tmp="$(mktemp --suffix=.png)"
  if python3 -I -c "import PIL" 2>/dev/null; then
    # Trim to the visible object (alpha > 24: generators leave faint haze at the edges), pad to a
    # square with a 4 % margin, scale with Lanczos. Colour is untouched.
    python3 -I - "$src" "$tmp" "$SIZE" <<'PY'
import sys
from PIL import Image
src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA")
mask = im.getchannel("A").point(lambda a: 255 if a > 24 else 0)
bbox = mask.getbbox() or (0, 0, im.width, im.height)
obj = im.crop(bbox)
side = int(max(obj.width, obj.height) * 1.08)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(obj, ((side - obj.width) // 2, (side - obj.height) // 2))
canvas.resize((size, size), Image.LANCZOS).save(dst, optimize=True)
PY
  else
    echo "sync_icons: Pillow not available — copying $id.png unscaled (Godot imports it with size_limit)" >&2
    cp "$src" "$tmp"
  fi
  if ! cmp -s "$tmp" "$dst"; then
    mv "$tmp" "$dst"
    chmod 644 "$dst"
    changed=$((changed + 1))
    echo "  icons/$id.png updated"
  else
    rm -f "$tmp"
  fi
  # Import settings: mipmaps + size limit, so a scaled-down slot stays sharp in the web build.
  imp="$dst.import"
  if [[ ! -f "$imp" ]]; then
    cat > "$imp" <<EOF
[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/icons/$id.png"

[params]

compress/mode=0
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=$SIZE
detect_3d/compress_to=1
EOF
  fi
done
echo "sync_icons: ${#ids[@]} icon(s), $changed file(s) copied → game/assets/icons"
