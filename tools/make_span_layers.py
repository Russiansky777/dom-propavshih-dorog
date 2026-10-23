#!/usr/bin/env python3
"""Первый пролёт (M25, блок 4): сцена поворота дня четвёртого и бревно-прогон отдельно, чтобы ворот Ильи его опускал.

G47/G48 (партия 9, assets/incoming/_meta_p9/README.md, «Координаты Z3»): основа — поворот дня четвёртого (фон Z3 + вода
fg_water + низкая вода днём state_water_low_day — на береговом камне плиты нет, G48), поверх — стройка
Z3_state_span_site_day4 (штабель из шести прогонов, ворот, ряж; без бревна) и отдельно бревно Z3_state_span_beam_day4
(только прогон). Делает две картинки холста 1672×941:
  game/assets/rooms/F_span/beam_waiting.png — сцена без бревна (основа дня 4 + стройка): фон крупного плана ворота и
      кадров F_span / F_span_done;
  game/assets/rooms/F_span/beam.png        — только бревно, в своих координатах холста: крупный план ворота
      (game/scripts/mechanics/windlass_panel.gd) поворачивает его вокруг берегового конца (1218, 570) — `pivot` в данных
      сцены M25; угол 0 — бревно на кольце опоры, как нарисовано (дальний конец (1112, 503) — `ring`).
Канат от ворота к бревну рисует игра (README партии 9). Прежняя версия (партия 5: бревно вырезалось из картины и место
заливалось) больше не нужна. --check — сверка без записи. Нужен Pillow. Запуск: python3 tools/make_span_layers.py [--check]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
Z3 = ROOT / "game" / "assets" / "rooms" / "Z3"
BASE = [Z3 / "bg.png", Z3 / "fg_water.png", Z3 / "state_water_low_day.png"]   # Z3 днём на четвёртый день (порядок слоёв Z3.json)
SITE = ROOT / "assets" / "incoming" / "Z3_state_span_site_day4.png"
BEAM = ROOT / "assets" / "incoming" / "Z3_state_span_beam_day4.png"
OUT = ROOT / "game" / "assets" / "rooms" / "F_span"


def build() -> tuple[Image.Image, Image.Image]:
    comp = Image.open(BASE[0]).convert("RGBA")
    for p in BASE[1:]:
        comp.alpha_composite(Image.open(p).convert("RGBA"))
    comp.alpha_composite(Image.open(SITE).convert("RGBA"))
    waiting = comp.convert("RGB")
    beam = Image.open(BEAM).convert("RGBA")
    return waiting, beam


def main() -> int:
    check = "--check" in sys.argv
    waiting, beam = build()
    bad = 0
    for name, im in (("beam_waiting.png", waiting), ("beam.png", beam)):
        target = OUT / name
        if check:
            same = target.exists() and ImageChops.difference(Image.open(target).convert(im.mode), im).getbbox() is None
            print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)}")
            bad += 0 if same else 1
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            im.save(target, optimize=True)
            print(f"wrote {target.relative_to(ROOT)} {im.size[0]}x{im.size[1]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
