#!/bin/bash
# Минимальный проект Godot для доработки анимаций Павла и Ильи (Директор 06.11, 23:54): собирает папку и zip из
# файлов игры (те же пути, что в game/) и стенда tools/anim_lab/. Проверка: tests/lab_smoke.gd внутри проекта.
#   tools/make_anim_lab.sh [out_dir]   → <out_dir>/anim_lab_pavel_ilya/ и <out_dir>/anim_lab_pavel_ilya.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/game"; LAB="$ROOT/tools/anim_lab"
OUT="${1:-$ROOT/build/anim_lab}"; D="$OUT/anim_lab_pavel_ilya"
mkdir -p "$OUT"; [ -e "$D" ] && mv "$D" "$D.old.$(date +%s)"
mkdir -p "$D/scripts/actors" "$D/shaders" "$D/data/actors" "$D/tests" "$D/lab" "$D/tools"
for s in actor_3d actor_life_3d arm_tone_modifier body_clear_modifier boot_fix_modifier skirt_drive_modifier npc_live_3d; do
	cp "$SRC/scripts/actors/$s.gd" "$SRC/scripts/actors/$s.gd.uid" "$D/scripts/actors/"; done
cp "$SRC/shaders/actor_3d.gdshader" "$SRC/shaders/actor_3d.gdshader.uid" "$D/shaders/"
for w in pavel ilya; do
	cp "$SRC/data/actors/$w.json" "$D/data/actors/"
	mkdir -p "$D/assets/characters/${w}_v3/rt3d"; cp "$SRC/assets/characters/${w}_v3/rt3d/"* "$D/assets/characters/${w}_v3/rt3d/"; done
for t in test_animation_state test_body_clear_state probe_hand_path probe_hands_closeup probe_shoulder_jelly probe_hand_penetration; do
	cp "$SRC/tests/$t.gd" "$D/tests/"; [ -f "$SRC/tests/$t.gd.uid" ] && cp "$SRC/tests/$t.gd.uid" "$D/tests/"; done
cp "$ROOT/tools/relax_hands.py" "$D/tools/"
cp "$LAB/lab/"* "$D/lab/"; cp "$LAB/tests/"* "$D/tests/"
cp "$LAB/project.godot" "$LAB/README.md" "$LAB/run.sh" "$LAB/run.bat" "$LAB/.gitignore" "$D/"
chmod +x "$D/run.sh"
(cd "$OUT" && rm -f anim_lab_pavel_ilya.zip && zip -qr anim_lab_pavel_ilya.zip anim_lab_pavel_ilya -x '*/.godot/*')
echo "$OUT/anim_lab_pavel_ilya.zip"
