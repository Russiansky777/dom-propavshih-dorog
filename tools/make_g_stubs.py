#!/usr/bin/env python3
"""Заглушки партии G до арта партии 9 (assets/manifest.json, batch 9): картинки, которые рисует слой `stub` (crops)
комнаты, пока заказанный файл не пришёл. Это не арт игры: как только assets/incoming/<id>.png ляжет и
tools/import_room_art.py положит его в game/assets/rooms/<LOC>/, заглушка не строится (validate_rooms п. 13).

  stub_shelf_leaning.png — H1, снятая полка у левого конца лежанки (заявка H1_state_shelf_leaning): та же полка,
      что полка B (assets/incoming/H1_state_shelf_table.png, доска без полотенца), в общем масштабе 92 px доски
      (как будущие H1_state_shelf_A / _B), поставлена на ребро и прислонена к лежанке; мягкая тень на полу.
  stub_bench_bare.png    — H1, лежанка без мокрого платка (заявка H1_state_bench_bare): место платка на фоне закрашено
      по соседним пикселям (cv2.inpaint), доска сиденья — открытый левый конец лавки, вытянутый вдоль неё, под
      сиденьем — тень. Грубо: только чтобы платок не лежал на лавке, когда он уже на крючке.

Запуск: python3 tools/make_g_stubs.py           — записать заглушки в game/assets/rooms/H1/
        python3 tools/make_g_stubs.py --check   — сверить (код 1 — расходятся)
Нужны Pillow, numpy и opencv (не в CI: результат в репозитории).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
H1 = ROOT / "game" / "assets" / "rooms" / "H1"
SRC_B = ROOT / "assets" / "incoming" / "H1_state_shelf_table.png"
BG = H1 / "bg.png"

BOARD_PX = 92.0                       # доска полки на холсте фона 1672×941 (одна для A, B и прислонённой)
SRC_BOARD = (47.0, 333.0)             # доска полки B в исходнике (make_h1_layers.py SRC_B_A / SRC_B_B)
SRC_BOX = (40, 288, 300, 100)         # доска с кронштейнами без полотенца сверху, x y w h
LEAN_DEG = 74.0                       # наклон: почти на ребре, верх к лавке
BENCH_BOX = (378, 480, 322, 160)      # лежанка с платком на фоне (заявка H1_state_bench_bare: x 378–700, y 480–640)
# платок на лежанке (верх у стены и свисающий край с бахромой), пиксели фона
TOWEL_POLY = [(380, 512), (470, 503), (560, 497), (640, 494), (700, 500), (700, 592), (660, 592), (600, 600), (540, 610),
              (470, 625), (420, 632), (383, 630)]


def shelf_leaning() -> Image.Image:
    src = Image.open(SRC_B).convert("RGBA")
    x, y, w, h = SRC_BOX
    board = src.crop((x, y, x + w, y + h))
    k = BOARD_PX / (SRC_BOARD[1] - SRC_BOARD[0])
    board = board.resize((round(w * k), round(h * k)), Image.LANCZOS)
    rot = board.rotate(LEAN_DEG, resample=Image.BICUBIC, expand=True)
    rot = rot.crop(rot.getbbox())
    # тень на полу: силуэт, сжатый по высоте, тёмный и мягкий, у нижнего конца
    pad = 14
    out = Image.new("RGBA", (rot.width + pad * 2, rot.height + pad), (0, 0, 0, 0))
    a = np.array(rot)[:, :, 3]
    sh = Image.fromarray((a * 0.35).astype(np.uint8)).resize((rot.width, max(6, rot.height // 8)))
    shadow = Image.new("RGBA", sh.size, (20, 12, 6, 0))
    shadow.putalpha(sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(3))
    out.alpha_composite(shadow, (pad + 6, out.height - sh.height - 2))
    out.alpha_composite(rot, (pad, 0))
    return out


def bench_bare() -> Image.Image:
    import cv2
    bg = np.array(Image.open(BG).convert("RGB"))
    hh, ww = bg.shape[:2]
    mask = np.zeros((hh, ww), np.uint8)
    cv2.fillPoly(mask, [np.array(TOWEL_POLY, np.int32)], 255)
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    inp = cv2.cvtColor(cv2.inpaint(cv2.cvtColor(bg, cv2.COLOR_RGB2BGR), mask, 9, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
    inp = inp.astype(np.float32)
    # сиденье: доска открытого левого конца лавки (между кочергами и платком), вытянутая вдоль — волокна идут вдоль
    plank = bg[528:553, 364:382].astype(np.float32)
    x0, x1 = 380, 700
    for x in range(x0, x1):
        t = (x - x0) / (x1 - x0)
        top = 528 - 14 * t              # лавка уходит вглубь к углу
        hgt = int(round(25 - 6 * t))
        col = plank[:, int((x - x0) * 0.37) % plank.shape[1]]
        col = cv2.resize(col.reshape(-1, 1, 3), (1, hgt)).reshape(-1, 3)
        y = int(round(top))
        inp[y:y + hgt, x] = col
        inp[y + hgt:y + hgt + 60, x] *= np.linspace(0.62, 0.97, 60)[:, None]   # тень под сиденьем
    x, y, w, h = BENCH_BOX
    patch = Image.fromarray(np.clip(inp, 0, 255).astype(np.uint8)[y:y + h, x:x + w]).convert("RGBA")
    patch.putalpha(Image.fromarray(mask[y:y + h, x:x + w]).filter(ImageFilter.GaussianBlur(3)))
    return patch


def main() -> int:
    check = "--check" in sys.argv
    bad = 0
    for name, fn in (("stub_shelf_leaning.png", shelf_leaning), ("stub_bench_bare.png", bench_bare)):
        im = fn()
        target = H1 / name
        if check:
            same = target.exists() and ImageChops.difference(Image.open(target).convert("RGBA"), im).getbbox() is None
            print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)}")
            bad += 0 if same else 1
        else:
            im.save(target, optimize=True)
            print(f"wrote {target.relative_to(ROOT)} {im.size[0]}x{im.size[1]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
