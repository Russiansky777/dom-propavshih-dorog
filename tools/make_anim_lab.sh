#!/bin/bash
# Минимальный проект Godot для доработки анимаций живых фигур (Директор 06.11, 23:54 — Павел и Илья; 07.11, 03:40 —
# «и по всем прочим персонажам»): собирает папку и zip из файлов игры (те же пути, что в game/) и стенда
# tools/anim_lab/. В стенд идут все персонажи, у которых в data/actors/*.json есть rt3d.scene; порядок и имена —
# data/story/characters.json. Таблица персонажей в README пересчитывается из данных при каждой сборке.
# Проверка: tests/lab_smoke.gd внутри проекта.
#   tools/make_anim_lab.sh [out_dir]   → <out_dir>/anim_lab/ и <out_dir>/anim_lab.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/game"; LAB="$ROOT/tools/anim_lab"
OUT="${1:-$ROOT/build/anim_lab}"; NAME=anim_lab; D="$OUT/$NAME"
mkdir -p "$OUT"; [ -e "$D" ] && mv "$D" "$D.old.$(date +%s)"
mkdir -p "$D/scripts/actors" "$D/shaders" "$D/data/actors" "$D/tests" "$D/lab" "$D/tools"
for s in actor_3d actor_life_3d arm_tone_modifier body_clear_modifier boot_fix_modifier skirt_drive_modifier npc_live_3d; do
	cp "$SRC/scripts/actors/$s.gd" "$SRC/scripts/actors/$s.gd.uid" "$D/scripts/actors/"; done
cp "$SRC/shaders/actor_3d.gdshader" "$SRC/shaders/actor_3d.gdshader.uid" "$D/shaders/"
for t in test_animation_state test_body_clear_state probe_hand_path probe_hands_closeup probe_shoulder_jelly probe_hand_penetration; do
	cp "$SRC/tests/$t.gd" "$D/tests/"; [ -f "$SRC/tests/$t.gd.uid" ] && cp "$SRC/tests/$t.gd.uid" "$D/tests/"; done
cp "$ROOT/tools/relax_hands.py" "$D/tools/"
cp "$LAB/lab/"* "$D/lab/"; cp "$LAB/tests/"* "$D/tests/"
cp "$LAB/project.godot" "$LAB/run.sh" "$LAB/run.bat" "$LAB/.gitignore" "$D/"
chmod +x "$D/run.sh"
# персонажи: данные, модель и её текстуры (файлы с тем же началом имени, что у GLB), список и таблица README
python3 - "$ROOT" "$D" "$LAB/README.md" <<'PY'
import json, os, shutil, sys
root, d, readme = sys.argv[1:4]
src = os.path.join(root, "game")
story = json.load(open(os.path.join(root, "data/story/characters.json")))["characters"]
chars, rows = [], []
for c in story:
    p = os.path.join(src, "data/actors/%s.json" % c["id"])
    if not os.path.exists(p):
        continue
    spec = json.load(open(p))
    rt = spec.get("rt3d") or {}
    scene = rt.get("scene", "")
    if not scene:
        continue
    shutil.copy(p, os.path.join(d, "data/actors"))
    glb = os.path.join(src, scene.replace("res://", ""))
    folder, stem = os.path.dirname(glb), os.path.splitext(os.path.basename(glb))[0]
    dst = os.path.join(d, os.path.relpath(folder, src))
    os.makedirs(dst, exist_ok=True)
    for f in sorted(os.listdir(folder)):
        if f.startswith(stem):
            shutil.copy(os.path.join(folder, f), dst)
    chars.append({"id": c["id"], "name": c["name"], "age": c.get("age"), "role": c.get("role", "")})
    clips = {k: v for k, v in rt.get("clips", {}).items() if not k.startswith("_")}
    roles = ("walk", "idle", "listen", "talk")
    extra = [k for k in clips if k not in roles]
    ab = rt.get("arm_body")
    if ab:
        bc = "до %g°; %s" % (ab.get("max_deg", 0), "в стойке руки как в клипе" if ab.get("stance_free") else "запечено: " + ", ".join(ab.get("bake", {}).get("roles", [])))
    else:
        bc = "нет"
    talk = clips.get("talk", "—")
    if talk in rt.get("concat", {}):
        talk += " = " + " + ".join(rt["concat"][talk].get("of", []))
    idle = "`%s`" % clips.get("idle", "—")
    pool = [x.get("clip") for x in rt.get("idle", {}).get("pool", []) if isinstance(x, dict)]
    if pool and pool != [clips.get("idle")]:
        idle = "пул: " + ", ".join("`%s`" % x for x in pool)
    listen = clips.get("listen", "= idle")
    rows.append("| %d | %s, %s | `%s` | %s | `%s` | `%s` | %s | %s | %s |" % (
        len(chars) % 10, c["name"], c.get("age", "?"), c["id"], idle, listen if listen != clips.get("idle") else "= idle",
        talk, ", ".join("`%s`" % e for e in extra) or "—", bc, ", ".join(rt.get("props", {}).keys()) or "—"))
json.dump(chars, open(os.path.join(d, "lab/characters.json"), "w"), ensure_ascii=False, indent=1)
table = "\n".join(["| Клавиша | Персонаж, возраст | id | idle | listen | talk | Разовые действия | BodyClear | Вещь в руке (не рисуется) |",
                   "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"] + rows)
text = open(readme).read()
a, b = "<!-- CHARACTERS -->", "<!-- /CHARACTERS -->"
i, j = text.index(a), text.index(b)
open(os.path.join(d, "README.md"), "w").write(text[:i + len(a)] + "\n" + table + "\n" + text[j:])
print("персонажей:", len(chars), ", ".join(c["id"] for c in chars))
PY
(cd "$OUT" && rm -f "$NAME.zip" && zip -qr "$NAME.zip" "$NAME" -x '*/.godot/*')
echo "$OUT/$NAME.zip"
