#!/bin/bash
# Живые жители (Директор 30.10: модели — живое 3D; «остальные чуточку попроще»): игровой GLB v2 (релиз npc-v2-work) → 120 тыс. треугольников, ткань матовая. Потом скопировать <имя>_rt.glb в game/assets/characters/<имя>_v2/rt3d/ (Godot вынесет текстуру рядом при импорте). 0 кредитов.
#   W=/tmp/npc_live PY=python3.13 tools/build_npc_live.sh
S="${W:-/tmp/npc_live}"; ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; mkdir -p "$S/n3d"
cd $S/n3d
for n in nina pavel mitya pelageya ilya ilya_wife ulyana; do
  f=${n}_v2_game_r4.glb
  if [ ! -s $f ]; then
    id=$(gh api repos/Russiansky777/dom-propavshih-dorog/releases/tags/npc-v2-work --jq ".assets[] | select(.name==\"$f\") | .id")
    gh api -H "Accept: application/octet-stream" repos/Russiansky777/dom-propavshih-dorog/releases/assets/$id > $f
  fi
  (cd "$ROOT" && timeout 1500 ${PY:-python3.13} pipeline/3d/build_rt3d_glb.py --base $S/n3d/$f --tris 120000 --matte --out $S/n3d/${n}_rt.glb --check-out $S/n3d/${n}_rt_check.json > $S/n3d/${n}_build.log 2>&1)
  echo "$n exit $? $(stat -c %s $S/n3d/${n}_rt.glb 2>/dev/null)"
done
# Павел, Митя ← ходьба Ильи; жена Ильи ← ходьба Нины (в их моделях v2 ходьбы нет): перенос клипа, затем снова 120 тыс.
get() { f=$1_v2_game_r4.glb; [ -s $f ] && return; id=$(gh api repos/Russiansky777/dom-propavshih-dorog/releases/tags/npc-v2-work --jq ".assets[] | select(.name==\"$f\") | .id"); gh api -H "Accept: application/octet-stream" repos/Russiansky777/dom-propavshih-dorog/releases/assets/$id > $f; }
for pair in pavel:ilya mitya:ilya ilya_wife:nina; do
  n=${pair%%:*}; src=${pair##*:}
  get $n; get $src
  echo "{\"character\": \"${n}_live\", \"actions\": [], \"retarget\": {\"library\": \"$S/n3d/${src}_v2_game_r4.glb\", \"roles\": {}, \"extra_clips\": [\"walk\"]}}" > req_$n.json
  (cd "$ROOT" && ${PY:-python3.13} pipeline/3d/retarget_clips.py --glb $S/n3d/${n}_v2_game_r4.glb --request $S/n3d/req_$n.json --state $S/n3d/none.json --out $S/n3d/${n}_walk.glb)
  (cd "$ROOT" && ${PY:-python3.13} pipeline/3d/build_rt3d_glb.py --base $S/n3d/${n}_walk.glb --tris 120000 --matte --out $S/n3d/${n}_rt.glb --check-out $S/n3d/${n}_rt_check.json)
done
echo ALLDONE
