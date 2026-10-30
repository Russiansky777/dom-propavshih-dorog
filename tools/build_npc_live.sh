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
  rm -f $S/n3d/$f
done
echo ALLDONE
