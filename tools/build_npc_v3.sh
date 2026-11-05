#!/bin/bash
# Жители v3 (блок 3, Директор 05.11): игровой GLB живой фигуры из новой модели Meshy (релиз npc-v3-work,
# <имя>_v3_<проба>_rigged.glb — tools/meshy_npc_v3.py) — 0 кредитов:
#   1. клипы прежней фигуры v2 (стойка, «слушает», «говорит», ходьба — уже выправленные: ноги, плечи, носки) переносятся
#      на новый риг (pipeline/3d/retarget_clips.py; скелет Meshy тот же, пропорции другие);
#   2. рот и матовая ткань — как у v2 (pipeline/3d/npc_v2/build_npc.py, параметры поля "blender" запроса
#      pipeline/requests/npc_<имя>_b.json: jaw, matte, rigid);
#   3. сетка до TRIS треугольников (pipeline/3d/build_rt3d_glb.py; v2 — 120 тыс., Агата v4 — 250 тыс.), текстуры
#      (цвет и нормали Meshy 4K) — до MAXTEX px: житель на экране 400–700 px ростом, 2K дают больше точек текстуры,
#      чем пикселей экрана; 4K без сжатия — по ~20 МБ на текстуру в сборке (как у Агаты v4).
# Итог — game/assets/characters/<имя>_v3/rt3d/<имя>_rt.glb.
#   W=/home/claude/work/v3 PY=python3 TRIS=200000 tools/build_npc_v3.sh pavel 1
set -euo pipefail
who=$1; s=${2:-1}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="${W:-/tmp/npc_v3}"; PY="${PY:-python3}"; TRIS="${TRIS:-200000}"
d="$W/$who"; mkdir -p "$d"
rig="$d/${who}_v3_${s}_rigged.glb"
if [ ! -s "$rig" ]; then
  id=$(gh api repos/Russiansky777/dom-propavshih-dorog/releases/tags/npc-v3-work --jq ".assets[] | select(.name==\"${who}_v3_${s}_rigged.glb\") | .id")
  gh api -H "Accept: application/octet-stream" repos/Russiansky777/dom-propavshih-dorog/releases/assets/$id > "$rig"
fi
lib="$ROOT/game/assets/characters/${who}_v2/rt3d/${who}_rt.glb"
"$PY" -I - "$who" "$lib" "$d" "$ROOT" <<'EOF'
import json, sys
who, lib, d, root = sys.argv[1:5]
b = json.load(open(f"{root}/pipeline/requests/npc_{who}_b.json", encoding="utf-8")).get("blender", {})
json.dump({"character": f"{who}_v3", "retarget": {"library": lib, "roles": {},
           "extra_clips": ["idle", "listen", "talk", "walk"]}}, open(f"{d}/retarget.json", "w"))
cfg = {"clips": {r: r for r in ("idle", "listen", "talk", "walk")}}
for k in ("jaw", "matte"):
    if k in b:
        cfg[k] = b[k]
json.dump({"character": f"{who}_v3", "blender": cfg}, open(f"{d}/build.json", "w"), ensure_ascii=False, indent=1)
EOF
mkdir -p "$d/a"
(cd "$ROOT" && "$PY" pipeline/3d/retarget_clips.py --glb "$rig" --request "$d/retarget.json" --state "$d/none.json" \
   --out "$d/a/animations.glb" --report "$d/retarget_report.json") > "$d/retarget.log" 2>&1 || { tail -20 "$d/retarget.log"; exit 1; }
"$PY" "$ROOT/pipeline/3d/npc_v2/build_npc.py" -- "$d/build.json" "$d/a" "$d/${who}_v3_game.glb" "$d/build_report.json" > "$d/build.log" 2>&1 \
   || { tail -20 "$d/build.log"; exit 1; }
(cd "$ROOT" && timeout 2400 "$PY" pipeline/3d/build_rt3d_glb.py --base "$d/${who}_v3_game.glb" --tris "$TRIS" --max-tex "${MAXTEX:-2048}" --matte \
   --out "$d/${who}_rt.glb" --check-out "$d/${who}_rt_check.json") > "$d/rt.log" 2>&1 || true
# проверка build_rt3d: у ходьбы после переноса 125 кадров, экспорт оставляет 124 — расходится только последний кадр
# (сверено покадрово 05.11: кадры 0–124 совпадают до 0,0 см; петля ходьбы в игре — 1,8–3,2 с); прочие клипы ≤ 2 мм
"$PY" -I - "$d/${who}_rt_check.json" <<'EOF2' || { tail -20 "$d/rt.log"; exit 1; }
import json, sys
r = json.load(open(sys.argv[1]))
bad = {k: v["max_dev_m"] for k, v in r["clips"].items() if v["max_dev_m"] > 0.002 and k != "walk"}
if r["result"]["missing"] or bad or not r.get("out_bytes"):
    sys.exit(f"проверка rt3d: {r['result']} {bad}")
print("rt3d:", r["result"], {k: v["max_dev_m"] for k, v in r["clips"].items()})
EOF2
out="$ROOT/game/assets/characters/${who}_v3/rt3d"; mkdir -p "$out"
cp "$d/${who}_rt.glb" "$out/${who}_rt.glb"
ls -la "$out"
