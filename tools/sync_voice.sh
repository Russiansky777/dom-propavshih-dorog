#!/usr/bin/env bash
# Copies the recorded voice lines the pipeline delivers in assets/voice/<lang>/ (*.ogg + manifest.json;
# src/ — the raw API answers — stays outside the game) into the Godot project game/assets/voice/<lang>/,
# so the game only reads its own copy (Claude Code never edits assets/ by hand; pipeline/voice writes it).
# Import: OGG Vorbis with loop=false. A missing .import file is written from a template (Godot fills
# uid/path on import); an existing one is forced to loop=false. Copies no longer in assets/ are removed.
#   tools/sync_voice.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="$ROOT/assets/voice"
DST_ROOT="$ROOT/game/assets/voice"
total=0
changed=0
for src in "$SRC_ROOT"/*/; do
  [[ -f "$src/manifest.json" ]] || continue
  lang="$(basename "$src")"
  dst="$DST_ROOT/$lang"
  mkdir -p "$dst"
  if ! cmp -s "$src/manifest.json" "$dst/manifest.json"; then
    cp "$src/manifest.json" "$dst/manifest.json"
    echo "  voice/$lang/manifest.json updated"
  fi
  for f in "$src"/*.ogg; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    total=$((total + 1))
    if ! cmp -s "$f" "$dst/$name"; then
      cp "$f" "$dst/$name"
      changed=$((changed + 1))
    fi
    imp="$dst/$name.import"
    if [[ ! -f "$imp" ]]; then
      cat > "$imp" <<'IMP'
[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[params]

loop=false
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
IMP
    elif ! grep -qx 'loop=false' "$imp"; then
      sed -i 's/^loop=.*/loop=false/' "$imp"
      grep -qx 'loop=false' "$imp" || printf '\n[params]\n\nloop=false\n' >> "$imp"
    fi
  done
  for f in "$dst"/*.ogg; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    if [[ ! -f "$src/$name" ]]; then
      rm -f "$f" "$f.import"
      echo "  voice/$lang/$name removed (not in assets/voice/$lang)"
    fi
  done
done
echo "sync_voice: $total line file(s), $changed copied → game/assets/voice"
