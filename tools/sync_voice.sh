#!/usr/bin/env bash
# Copies the recorded voice lines the pipeline delivers in assets/voice/<lang>/ (*.ogg + manifest.json;
# src/ — the raw API answers — stays outside the game) into the Godot project game/assets/voice/<lang>/,
# so the game only reads its own copy (Claude Code never edits assets/ by hand; pipeline/voice writes it).
# Import: OGG Vorbis with loop=false. A missing .import file is written in full (uid, path, deps — what Godot would
# write, so its import changes nothing); an existing one is forced to loop=false. Copies no longer in assets/ are removed.
# Subfolders are copied too (narrator/<key>.ogg — the voice-over lines, data/story/voice.json → narration);
# src/ (API answers) never reaches the game.
#   tools/sync_voice.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="$ROOT/assets/voice"
DST_ROOT="$ROOT/game/assets/voice"
total=0
changed=0
# 09.11: lines shortened for the game (data/story/voice_trim.json → tools/voice_trim.py): looked up here once, so the
# thousands of other lines do not each start a Python
declare -A TRIM=()
while IFS= read -r k; do
  [[ -n "$k" ]] && TRIM["$k"]=1
done < <(python3 -c 'import json,sys; [print(k) for k in json.load(open(sys.argv[1], encoding="utf-8")).get("trims", {})]' "$ROOT/data/story/voice_trim.json" 2>/dev/null || true)
for src in "$SRC_ROOT"/*/; do
  src="${src%/}"
  [[ -f "$src/manifest.json" ]] || continue
  lang="$(basename "$src")"
  # ru_takes — дубли для страницы прослушивания (tools/listen_page.py, apply_takes.py): игра их не читает, в сборку не идут
  # (ревью 01.11, Д-2: 30 МБ дублей ехали в каждую сборку)
  [[ "$lang" == *_takes ]] && continue
  dst="$DST_ROOT/$lang"
  mkdir -p "$dst"
  # the game's manifest: the pipeline's, with trimmed lines' text (tools/voice_trim.py --manifest)
  python3 "$ROOT/tools/voice_trim.py" --manifest "$src/manifest.json" "$dst/manifest.json" "$lang"
  while IFS= read -r -d '' f; do
    name="${f#"$src"/}"
    total=$((total + 1))
    mkdir -p "$(dirname "$dst/$name")"
    # 09.11: a line shortened for the game (data/story/voice_trim.json — the lamp of Ilya's wife taken out of M20_7)
    if [[ -n "${TRIM["$lang/$name"]:-}" ]] && python3 "$ROOT/tools/voice_trim.py" "$f" "$dst/$name" "$lang/$name" </dev/null; then
      :
    elif ! cmp -s "$f" "$dst/$name"; then
      cp "$f" "$dst/$name"
      changed=$((changed + 1))
    fi
    imp="$dst/$name.import"
    if [[ ! -f "$imp" ]]; then
      # The full .import Godot itself would write (uid, path, deps): Godot keeps it as is, so a fresh checkout's import
      # leaves git clean. path/dest_files — md5 of the res:// path (Godot's scheme); uid — derived from the same path
      # (Godot's text form: base 34, letters a–y and digits 0–8), stable across runs and machines.
      python3 - "$lang" "$name" "$imp" <<'PY'
import hashlib, sys
lang, name, out = sys.argv[1:4]
res = f"res://assets/voice/{lang}/{name}"
h = hashlib.md5(res.encode("utf-8")).hexdigest()
v = int(hashlib.md5(("uid|" + res).encode("utf-8")).hexdigest()[:16], 16) & 0x7FFFFFFFFFFFFFFF
uid = ""
while True:
    c = v % 34
    uid = (chr(ord("a") + c) if c < 25 else chr(ord("0") + c - 25)) + uid
    v //= 34
    if v == 0:
        break
base = name.rsplit("/", 1)[-1]
dest = f"res://.godot/imported/{base}-{h}.oggvorbisstr"
open(out, "w", encoding="utf-8").write(f"""[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"
uid="uid://{uid}"
path="{dest}"

[deps]

source_file="{res}"
dest_files=["{dest}"]

[params]

loop=false
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
""")
PY
    elif ! grep -qx 'loop=false' "$imp"; then
      sed -i 's/^loop=.*/loop=false/' "$imp"
      grep -qx 'loop=false' "$imp" || printf '\n[params]\n\nloop=false\n' >> "$imp"
    fi
  done < <(find "$src" -path "$src/src" -prune -o -type f -name '*.ogg' -print0 | sort -z)
  while IFS= read -r -d '' f; do
    name="${f#"$dst"/}"
    if [[ ! -f "$src/$name" ]]; then
      rm -f "$f" "$f.import"
      echo "  voice/$lang/$name removed (not in assets/voice/$lang)"
    fi
  done < <(find "$dst" -type f -name '*.ogg' -print0)
done
echo "sync_voice: $total line file(s), $changed copied → game/assets/voice"
