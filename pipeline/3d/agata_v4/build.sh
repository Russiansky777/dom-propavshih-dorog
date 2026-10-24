#!/usr/bin/env bash
# Агата v4 (T5b, 24.10): сборка игрового GLB из задач Meshy — порядок шагов и параметры, как в запуске 40093021019.
# Нужен Python 3.13 с bpy 5.2.2, numpy, pillow, scipy (bpy = pipeline/requirements.txt; scipy — для маски и KD-дерева).
# Ссылки на файлы Meshy — в pipeline/3d/state/agata_v4_*.json (истекают через 3 дня после задачи; потом — GET задачи по id).
#   W=/tmp/agata_v4 PY=python3.13 pipeline/3d/agata_v4/build.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
D="$ROOT/pipeline/3d/agata_v4"; W="${W:-/tmp/agata_v4}"; PY="${PY:-python3}"
mkdir -p "$W"
url() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))" "$ROOT/pipeline/3d/state/$1" "$2"; }
get() { [ -f "$W/$2" ] || curl -sL -m 900 "$1" -o "$W/$2"; }
# 1. исходная модель 01a16bb8 (T5a) и Retexture 01a16ddb (лицо, волосы; одежда в нём уехала в оранжевый — не берём)
get "$(url agata_v4_model.json "d['model_urls']['glb']")" model_v4.glb
get "$(url agata_v4_retexture.json "d['model_urls']['glb']")" retex.glb
$PY "$D/dump_tex.py" -- "$W/model_v4.glb" "$W/model_v4" 2>/dev/null || true
# базовые цвета обеих моделей (UV совпадают: enable_original_uv) → маска лица и волос по геометрии → смешение
$PY "$D/headmask.py" -- "$W/model_v4.glb" "$W/model_v4_BaseColor.png" "$W/headmask.png"
$PY -I "$D/composite.py" "$W/model_v4_BaseColor.png" "$W/retex_BaseColor.png" "$W/headmask.png" "$W/v4_BaseColor.png"
# 2. GLB для рига: исходная геометрия, упрощение до 290 тыс. треугольников (UV те же) — риг Meshy по ссылке (релиз agata-v4-work)
$PY "$D/build_rig_input.py" -- "$W/model_v4.glb" "$W/v4_BaseColor.png" "$W/agata_v4_rig_input.glb"
# 3. риг 01a16dea + стойка Text to Motion 01a16ddd (motion.glb), присед Collect_Object 01a16df5 (actions.glb)
get "$(url agata_v4_motion.json "d['result']['animation_glb_url']")" motion.glb
get "$(url agata_v4_actions.json "d['result']['animation_glb_url']")" actions.glb
$PY "$D/prep_idle.py" -- "$W/motion.glb" "$W/base_idle.glb" 18 48 0.5          # амплитуда ×0,5 вокруг средней позы окна
$PY "$D/v4_fix.py" -- "$W/base_idle.glb" "$W/base_fixed.glb" "$W/fix_report.json"  # угол платка, жёсткие сумка и ремень
$PY "$D/merge_actions.py" -- "$W/base_fixed.glb" "$W/base_all.glb" "$W/actions.glb=Collect_Object"
# 4. клипы игры (перенос с v3 — 0 кредитов), правая рука на 12° от корпуса во всех клипах
echo '{"actions": {"idle": {"key": "Idle_T2M"}, "pick": {"key": "Collect_Object"}}}' > "$W/state_local.json"
(cd "$ROOT" && $PY pipeline/3d/retarget_clips.py --glb "$W/base_all.glb" --request "$D/retarget_local.json" \
   --state "$W/state_local.json" --out "$W/anim_rt.glb" --clips-out "$W/clips.txt" --report "$W/retarget.json")
$PY "$D/arm_offset.py" -- "$W/anim_rt.glb" "$W/agata_v4_animations.glb" 12
# 5. проверка: ремень и сумка без костей рук, растяжение, зазор кисть ↔ сумка по всем клипам
$PY "$D/check_bag.py" -- "$W/agata_v4_animations.glb" "$W/base_fixed.glb.strap_co.npy" "$W/bag_check.json" 3
echo "готово: $W/agata_v4_animations.glb → релиз agata-v4-work → pipeline/requests/agata_v4_t5b.json (stages: local_glb)"
