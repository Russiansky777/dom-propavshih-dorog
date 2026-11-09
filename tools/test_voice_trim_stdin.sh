#!/usr/bin/env bash
# 09.11, 20:30: voice_trim.py must not read its stdin — sync_voice.sh calls it inside a `while read` over find -print0,
# and ffmpeg (console on stdin) ate the "/" of the next path: «cp: cannot stat 'home/…'», the run stopped before ru/.
# Self-check: the old way (ffmpeg without -nostdin, stdin inherited) eats the bytes — the test sees it.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
src="$ROOT/assets/voice/ru/M20_7.ogg"
[[ -f "$src" ]] || { echo "[voice_trim stdin] skipped: no $src"; exit 0; }
command -v ffmpeg >/dev/null || { echo "[voice_trim stdin] skipped: no ffmpeg"; exit 0; }
probe='/next/path/one.ogg'
left="$( { python3 "$ROOT/tools/voice_trim.py" "$src" "$TMP/out.ogg" "ru/M20_7.ogg" >/dev/null 2>&1; cat; } <<<"$probe" )"
ok=0
if [[ "$left" == "$probe" ]]; then echo "PASS  voice_trim leaves stdin alone"; else echo "FAIL  voice_trim ate stdin: left «$left»"; ok=1; fi
# self-check: ffmpeg with an inherited stdin does eat it (so the check above can fail)
eaten="$( { ffmpeg -v error -y -i "$src" -t 0.5 -f null - >/dev/null 2>&1; cat; } <<<"$probe" )"
if [[ "$eaten" != "$probe" ]]; then echo "PASS  self-check: ffmpeg with stdin eats «${probe:0:${#probe}-${#eaten}}»"; else echo "WARN  self-check: this ffmpeg left stdin alone (cannot show the defect here)"; fi
exit $ok
