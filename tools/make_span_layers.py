#!/usr/bin/env python3
"""Первый пролёт (M25, блок 4): бревно-прогон отдельно от картины, чтобы ворот Ильи его опускал.

Из поставки партии 5 (assets/incoming/Z3_bg.png + Z3_state_beam.png — бревно уже лежит с берега на ближней опоре,
ворот с канатом, штабель прогонов) делает две картинки холста 1672×941:
  game/assets/rooms/F_span/beam_waiting.png — та же сцена без бревна: место бревна заполнено по соседним пикселям
      (OpenCV inpaint, Telea) — вода, верх опоры, береговой ряж; канат от ворота остаётся;
  game/assets/rooms/F_span/beam.png        — только бревно (прозрачное вокруг), в своих координатах холста:
      крупный план ворота (game/scripts/mechanics/windlass_panel.gd) поворачивает его вокруг берегового конца
      (`pivot` в данных сцены M25) — угол 0 — бревно на кольце опоры, как в поставке.
Контур бревна BEAM_POLY — по картинке (верхняя и нижняя кромки, торец у ряжа). --check — сверка без записи.
Нужны Pillow, numpy, opencv-python. Запуск: python3 tools/make_span_layers.py [--check]
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC_BG = ROOT / "assets" / "incoming" / "Z3_bg.png"
SRC_BEAM = ROOT / "assets" / "incoming" / "Z3_state_beam.png"
OUT = ROOT / "game" / "assets" / "rooms" / "F_span"
# Бревно на холсте 1672×941: от верха ближней опоры (дальний конец, x≈990) к береговому ряжу (торец x≈1245, y≈572).
BEAM_POLY = [(984, 446), (992, 431), (1006, 428), (1215, 528), (1252, 547), (1268, 560), (1271, 580), (1262, 596),
             (1243, 601), (1222, 594), (1196, 578), (990, 468)]

CRIB_X, CRIB_DY = 1190, 34     # береговой ряж под торцом — брёвна ряжа ниже
PIER_X, PIER_DY = 1012, 22     # верх ближней опоры под дальним концом — её же камни ниже
WATER_DY = 58                  # вода — та же рябь выше по столбцу


def build() -> tuple[Image.Image, Image.Image]:
    bg = Image.open(SRC_BG).convert("RGBA")
    comp = bg.copy()
    comp.alpha_composite(Image.open(SRC_BEAM).convert("RGBA"))
    mask = Image.new("L", comp.size, 0)
    ImageDraw.Draw(mask).polygon(BEAM_POLY, fill=255)
    soft = mask.filter(ImageFilter.GaussianBlur(1.2))
    beam = Image.new("RGBA", comp.size, (0, 0, 0, 0))
    beam.paste(comp, (0, 0), soft)
    # The hole is filled by texture from the same column a little higher (water ripples run along rows; the near
    # pier's top takes its own stones from below the beam end), the crib end by the logs under it; then a thin
    # Telea pass blends the seams.
    grow = np.array(mask.filter(ImageFilter.MaxFilter(9))) > 0
    rgb = np.array(comp.convert("RGB"))
    out = rgb.copy()
    ys, xs = np.nonzero(grow)
    for y, x in zip(ys, xs):
        if x >= CRIB_X:
            sy = y + CRIB_DY
        elif x <= PIER_X:
            sy = y + PIER_DY
        else:
            sy = y - WATER_DY
        sy = min(max(sy, 0), rgb.shape[0] - 1)
        out[y, x] = rgb[sy, x]
    edge = np.array(Image.fromarray((grow * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) ^ \
        np.array(Image.fromarray((grow * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5)))
    bgr = cv2.cvtColor(out, cv2.COLOR_RGB2BGR)
    bgr = cv2.inpaint(bgr, (edge > 0).astype(np.uint8) * 255, 3, cv2.INPAINT_TELEA)
    waiting = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
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
