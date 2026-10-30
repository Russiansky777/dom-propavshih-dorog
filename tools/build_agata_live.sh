#!/usr/bin/env bash
# Живая Агата v4 для игры (решение Директора 30.10: модели — живое 3D, Steam). 0 кредитов Meshy.
#   W=/tmp/agata_live PY=python3.13 tools/build_agata_live.sh
# Нужен Python 3.13 с bpy 5.2.2 и numpy (pipeline/requirements.txt), gh с доступом к репозиторию.
#  1. GLB листов v4 (T5c, релиз agata-v4-work: agata_v4_animations_t5c.glb — сетка 381 тыс., текстура 4K, клипы листов);
#  2. retarget_clips.py — к её клипам переносятся с библиотеки прежней Агаты (pipeline/3d/motions/agata_rev10_clips.glb)
#     спокойные стойки, «вдох и оглядеться», Casual_Walk и жест реплики (ноги — из её стойки Idle_T2M_idle);
#  3. build_rt3d_glb.py — сетка до 250 тыс. треугольников (до Armature: веса и UV те же), ткань матовая, все клипы в одном
#     файле, проверка костей после экспорта (≤ 2 мм);
#  4. копия в game/assets/characters/agata/rt3d/agata_v4_rt.glb (Godot при импорте выносит текстуры рядом: без потерь,
#     с MIP-уровнями — .import в репозитории).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="${W:-/tmp/agata_live}"; PY="${PY:-python3.13}"
mkdir -p "$W"
REPO=Russiansky777/dom-propavshih-dorog
if [ ! -f "$W/agata_v4_t5c.glb" ]; then
  id=$(gh api "repos/$REPO/releases/tags/agata-v4-work" --jq '.assets[] | select(.name=="agata_v4_animations_t5c.glb") | .id')
  gh api -H "Accept: application/octet-stream" "repos/$REPO/releases/assets/$id" > "$W/agata_v4_t5c.glb"
fi
cat > "$W/req.json" <<'EOF'
{
  "character": "agata_v4_live",
  "actions": ["idle", "talk"],
  "retarget": {
    "library": "pipeline/3d/motions/agata_rev10_clips.glb",
    "roles": {
      "idle": {"own": true, "name": "idle_ref"},
      "talk": {"clip": "Talk_with_Right_Hand_Open", "blend_from": "idle", "legs_from": "idle", "blend_s": 0.5, "name": "Talk_with_Right_Hand_Open"}
    },
    "extra_clips": ["Idle_4", "Idle_3", "Idle_9", "Idle_7", "Idle_12", "Idle_6", "Short_Breathe_and_Look_Around", "Long_Breathe_and_Look_Around", "Casual_Walk"],
    "drop_own": ["idle_ref"]
  }
}
EOF
echo '{"actions": {"idle": {"key": "Idle_T2M_idle"}}}' > "$W/state.json"
cd "$ROOT"
$PY pipeline/3d/retarget_clips.py --glb "$W/agata_v4_t5c.glb" --request "$W/req.json" --state "$W/state.json" \
  --out "$W/agata_v4_plus.glb" --clips-out "$W/clips.txt" --report "$W/retarget.json"
$PY pipeline/3d/build_rt3d_glb.py --base "$W/agata_v4_plus.glb" --tris 250000 --drop Idle_T2M Collect_Object --matte \
  --out "$W/agata_v4_rt.glb" --check-out "$W/agata_v4_rt_check.json"
cp "$W/agata_v4_rt.glb" game/assets/characters/agata/rt3d/agata_v4_rt.glb
echo "готово: game/assets/characters/agata/rt3d/agata_v4_rt.glb ($(stat -c %s "$W/agata_v4_rt.glb") байт); отчёт $W/agata_v4_rt_check.json"
