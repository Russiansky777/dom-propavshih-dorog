#!/usr/bin/env bash
# Руки жителей вдоль тела: пересчёт кривых game/data/actors_rest/<id>.json (scripts/actors/arm_rest.gd).
# Нужен после смены модели жителя, его клипов стойки/разговора или параметров rt3d.arm_body (оболочка одежды).
#   tools/bake_arm_rest.sh [id,id,…|all]        — пересчитать и записать
#   tools/bake_arm_rest.sh all check            — только сверить с файлами (код 1 при расхождении > 1°)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/godot_env.sh"
"$GODOT" --headless --audio-driver Dummy --path "$ROOT/game" -s res://tests/bake_arm_rest.gd -- "${1:-all}" ${2:-}
