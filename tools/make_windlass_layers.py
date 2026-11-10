#!/usr/bin/env python3
"""Ворот Ильи крутится (Директор 10.11, 16:15: «чтобы как-то крутился реально ворот у Ильи… оживить его, установку эту»).

В картине стройки (game/assets/rooms/F_span/beam_waiting.png, tools/make_span_layers.py) ворот нарисован целиком:
барабан с витками каната между двумя стойками и две рукояти (левая вверх, правая вниз). Чтобы он крутился в крупном
плане первого пролёта (game/scripts/mechanics/windlass_panel.gd → WindlassSpin), из картины делаются части:
  windlass_clean.png  — заплата на места обеих нарисованных рукоятей: тот же грунт рядом, вклеенный без шва
                        (cv2.seamlessClone), альфа — только эти места; ступицы оси остаются нарисованными;
  windlass_grip_l.png, windlass_grip_r.png — деревянные ручки рукоятей, вырезанные из картины (их несёт плечо,
                        которое рисует игра);
  windlass_drum.png   — витки каната на барабане (их узор игра сдвигает вдоль оси: намотка идёт);
  windlass.json       — где что лежит на холсте 1672×941 (заплата, ручки и их точки крепления, оси, барабан).
--check — части на диске совпадают с тем, что получается из картины. Нужны numpy, OpenCV.
  python3 tools/make_windlass_layers.py [--check]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "rooms" / "F_span"
SRC = OUT / "beam_waiting.png"

# Нарисованные рукояти (холст): многоугольник и откуда брать грунт взамен (сдвиг источника).
CRANKS = {
    "l": {"poly": [(893, 559), (931, 561), (933, 575), (928, 601), (915, 601), (918, 577), (893, 575)], "from": (38, -34)},
    "r": {"poly": [(1049, 622), (1061, 618), (1071, 641), (1099, 645), (1099, 661), (1057, 657)], "from": (46, 18)},
}
# Ручки: многоугольник в картине и точка, где ручка сидит на плече.
GRIPS = {   # брусок ручки: ось от конца до конца и полутолщина — вырез точно по дереву, без грунта вокруг
    "l": {"line": [(896.0, 568.5), (927.0, 570.0)], "r": 4.0, "joint": (926, 569)},
    "r": {"line": [(1063.0, 647.0), (1093.0, 652.0)], "r": 5.0, "joint": (1064, 648)},
}
# Оси рукоятей (центр ступицы) и размах плеча на экране: плечо ходит в плоскости поперёк оси ворота, а смотрим мы на
# ворот почти сбоку — круг виден узким овалом (rx по горизонтали); в покое плечо стоит ровно как нарисовано.
AXLES = {"l": (921, 604), "r": (1051, 616)}
ARM = {"rx": 9.0, "width": 6.0}   # высоту овала и его сдвиг вдоль оси игра берёт из нарисованных плеч (ось → точка ручки)
# Витки каната на барабане: прямоугольник и шаг витка (px холста).
DRUM = {"rect": (948, 588, 49, 54), "pitch": 6.0,   # шаг витка вдоль оси — замер автокорреляцией по середине барабана (5,75–6,5)
        "poly": [(948, 595), (997, 590), (997, 636), (948, 641)]}


def poly_mask(shape, poly, grow=0, feather=0.0) -> np.ndarray:
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [np.array(poly, np.int32)], 255)
    if grow:
        m = cv2.dilate(m, np.ones((grow, grow), np.uint8))
    if feather > 0:
        m = cv2.GaussianBlur(m, (0, 0), feather)
    return m


def capsule_mask(shape, line, r: float) -> np.ndarray:
    """Мягкая маска бруска: расстояние до отрезка ≤ r (край — полпикселя)."""
    (x0, y0), (x1, y1) = line
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]].astype(np.float32)
    dx, dy = x1 - x0, y1 - y0
    t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
    d = np.hypot(xx - (x0 + t * dx), yy - (y0 + t * dy))
    return (np.clip(r + 0.5 - d, 0.0, 1.0) * 255).astype(np.uint8)


def build() -> dict:
    im = cv2.imread(str(SRC), cv2.IMREAD_COLOR)
    if im is None:
        raise SystemExit(f"нет картины {SRC}")
    clean = im.copy()
    hole = np.zeros(im.shape[:2], np.uint8)
    for c in CRANKS.values():
        m = poly_mask(im.shape, c["poly"], grow=5)
        ys, xs = np.where(m > 0)
        x0, x1, y0, y1 = xs.min() - 3, xs.max() + 4, ys.min() - 3, ys.max() + 4
        dx, dy = c["from"]
        src = im[y0 + dy:y1 + dy, x0 + dx:x1 + dx].copy()
        clean = cv2.seamlessClone(src, clean, m[y0:y1, x0:x1].copy(), ((x0 + x1) // 2, (y0 + y1) // 2), cv2.NORMAL_CLONE)
        hole |= m
    ys, xs = np.where(hole > 0)
    px0, py0, px1, py1 = int(xs.min()) - 4, int(ys.min()) - 4, int(xs.max()) + 5, int(ys.max()) + 5
    alpha = cv2.GaussianBlur(cv2.dilate(hole, np.ones((3, 3), np.uint8)), (0, 0), 1.2)
    patch = np.dstack([clean[py0:py1, px0:px1], alpha[py0:py1, px0:px1]])
    out = {"windlass_clean.png": patch}
    meta = {"_comment": "tools/make_windlass_layers.py — части ворота для WindlassSpin; холст 1672×941",
            "clean": {"file": "windlass_clean.png", "at": [px0, py0]}, "axles": {k: list(v) for k, v in AXLES.items()},
            "arm": ARM, "grips": {}, "drum": {}}
    for k, g in GRIPS.items():
        m = capsule_mask(im.shape, g["line"], g["r"])
        ys, xs = np.where(m > 8)
        x0, x1, y0, y1 = int(xs.min()) - 1, int(xs.max()) + 2, int(ys.min()) - 1, int(ys.max()) + 2
        out[f"windlass_grip_{k}.png"] = np.dstack([im[y0:y1, x0:x1], m[y0:y1, x0:x1]])
        meta["grips"][k] = {"file": f"windlass_grip_{k}.png", "at": [x0, y0], "joint": list(g["joint"]),
                            "far": list(g["line"][0] if k == "l" else g["line"][1])}   # свободный конец ручки
    dx, dy, dw, dh = DRUM["rect"]
    dm = poly_mask(im.shape, DRUM["poly"], feather=0.8)
    out["windlass_drum.png"] = np.dstack([im[dy:dy + dh, dx:dx + dw], dm[dy:dy + dh, dx:dx + dw]])
    (ax0, ay0), (ax1, ay1) = DRUM["poly"][0], DRUM["poly"][1]
    meta["drum"] = {"file": "windlass_drum.png", "at": [dx, dy], "size": [dw, dh], "pitch": DRUM["pitch"],
                    "slope": round((ay1 - ay0) / (ax1 - ax0), 4)}
    out["windlass.json"] = meta
    return out


def main() -> int:
    check = "--check" in sys.argv
    parts = build()
    bad = 0
    for name, data in parts.items():
        p = OUT / name
        if name.endswith(".json"):
            text = json.dumps(data, ensure_ascii=False, indent=1) + "\n"
            if check:
                if not p.exists() or p.read_text(encoding="utf-8") != text:
                    print(f"РАСХОЖДЕНИЕ {name}")
                    bad += 1
            else:
                p.write_text(text, encoding="utf-8")
            continue
        if check:
            cur = cv2.imread(str(p), cv2.IMREAD_UNCHANGED)
            # не «точка в точку»: бесшовная вклейка (seamlessClone) у разных версий OpenCV расходится на единицы
            if cur is None or cur.shape != data.shape or float(np.abs(cur.astype(int) - data.astype(int)).mean()) > 1.0:
                print(f"РАСХОЖДЕНИЕ {name}")
                bad += 1
        else:
            cv2.imwrite(str(p), data)
    print(f"make_windlass_layers: {'сверка' if check else 'записано'} {len(parts)} частей, расхождений {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
