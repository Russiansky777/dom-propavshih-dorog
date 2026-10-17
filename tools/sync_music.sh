#!/usr/bin/env bash
# Copies the music themes Codex/the pipeline delivers in assets/music/*.ogg into the Godot project
# (game/assets/music/), so the game only reads its own copy (Claude Code never edits assets/).
# Import: OGG Vorbis with loop=false — the seamless loop is MusicDirector's crossfade
# (game/scripts/audio/music_director.gd), Suno tracks are not sample-accurate loops. A missing
# .import file is written from a template (Godot fills uid/path on import); an existing one is
# forced to loop=false. Copies that no longer exist in assets/music are removed.
#   tools/sync_music.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/music"
DST="$ROOT/game/assets/music"
mkdir -p "$DST"
changed=0
for f in "$SRC"/*.ogg; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  if ! cmp -s "$f" "$DST/$name"; then
    cp "$f" "$DST/$name"
    changed=$((changed + 1))
    echo "  music/$name updated"
  fi
  imp="$DST/$name.import"
  if [[ ! -f "$imp" ]]; then
    cat > "$imp" <<'EOF'
[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[params]

loop=false
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
EOF
  elif ! grep -qx 'loop=false' "$imp"; then
    sed -i 's/^loop=.*/loop=false/' "$imp"
    grep -qx 'loop=false' "$imp" || printf '\n[params]\n\nloop=false\n' >> "$imp"
    echo "  music/$name.import: loop=false"
  fi
done
for f in "$DST"/*.ogg; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f")"
  if [[ ! -f "$SRC/$name" ]]; then
    rm -f "$f" "$f.import"
    echo "  music/$name removed (not in assets/music)"
  fi
done
echo "sync_music: $(find "$DST" -name '*.ogg' | wc -l) theme file(s), $changed copied → game/assets/music"
