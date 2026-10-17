#!/usr/bin/env bash
# Звуки: исходники ElevenLabs assets/sfx_src/*.wav → game/assets/sfx/ (нарезка шагов, двери, сумка,
# бесшовные петли дождя и огня OGG, измерения громкости levels.json). Подробности — tools/prepare_sfx.py.
# Результат коммитится; в CI не запускается (нужны numpy, scipy, ffmpeg).
# Скрипт лежит в tools/, а не в pipeline/: pipeline/ и assets/ по CLAUDE.md принадлежат Codex, а игра
# читает только свою копию в game/assets/.
#   tools/prepare_sfx.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/prepare_sfx.py" "$@"
