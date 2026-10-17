#!/usr/bin/env bash
# Copies data/story/ into game/data/story/ (Godot reads res://data/story). Symlinks are avoided on
# purpose: git on Windows would check them out as text files. Run before tests/exports (scripts do).
#
# Atomic per file: several agents run tests in the same tree at once. The old fallback (rm -rf the
# whole folder, then copy) let a parallel Godot run read a half-empty folder — flaky
# «O2: no Ambient node» (18.10). Now only changed files are replaced, each by write-to-temp + rename,
# and stale files are removed one by one; a reader sees either the old or the new file, never none.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/data/story"
DST="$ROOT/game/data/story"
mkdir -p "$DST"
changed=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  out="$DST/$rel"
  if ! cmp -s "$f" "$out"; then
    mkdir -p "$(dirname "$out")"
    tmp="$out.sync.$$"
    cp "$f" "$tmp"
    mv -f "$tmp" "$out"
    changed=$((changed + 1))
  fi
done < <(find "$SRC" -name '*.json' -type f -print0)
removed=0
while IFS= read -r -d '' f; do
  rel="${f#"$DST"/}"
  if [[ ! -e "$SRC/$rel" ]]; then
    rm -f "$f"
    removed=$((removed + 1))
  fi
done < <(find "$DST" -name '*.json' -type f -print0)
# Godot should not import JSON as resources; .gdignore is NOT used (it would hide the files from export).
echo "[data] synced $(find "$DST" -name '*.json' | wc -l) json files → game/data/story (changed $changed, removed $removed)"
