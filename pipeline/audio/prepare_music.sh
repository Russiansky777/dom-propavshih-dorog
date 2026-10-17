#!/usr/bin/env bash
# Музыка: WAV-оригиналы Suno (хранятся у Директора, в репозиторий не кладём) → OGG Vorbis для игры.
# Громкость: двухпроходный loudnorm, линейно (без компрессии), −18 LUFS integrated, true peak −1.5 dBTP.
# Использование: pipeline/audio/prepare_music.sh <папка_с_wav> → assets/music/<имя>.ogg (имя файла WAV = имя темы)
set -euo pipefail
src="$1"; out="$(cd "$(dirname "$0")/../.." && pwd)/assets/music"; mkdir -p "$out"
for f in "$src"/*.wav; do
  n=$(basename "$f" .wav)
  m=$(ffmpeg -hide_banner -nostats -i "$f" -af loudnorm=I=-18:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | sed -n '/^{/,/^}/p')
  read -r I TP LRA TH OFF < <(echo "$m" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['input_i'],d['input_tp'],d['input_lra'],d['input_thresh'],d['target_offset'])")
  ffmpeg -hide_banner -loglevel error -y -i "$f" -af "loudnorm=I=-18:TP=-1.5:LRA=11:measured_I=$I:measured_TP=$TP:measured_LRA=$LRA:measured_thresh=$TH:offset=$OFF:linear=true,aresample=48000" -c:a libvorbis -q:a 5 "$out/$n.ogg"
  echo "$n: $I LUFS → −18 LUFS"
done
