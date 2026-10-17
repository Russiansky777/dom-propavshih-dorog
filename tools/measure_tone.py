#!/usr/bin/env python3
"""Яркость и тон актёра против пола рядом с ним — по паре кадров из game/tests/shots_lighting.gd
(сценарии с "pair": <имя>.png — с Агатой, <имя>_bg.png — тот же миг без неё).

Фигура = пиксели, где кадры различаются (> 14 по любому каналу) ВЫШЕ ступней на 40 px (ниже лежат
тени — они тоже исчезают вместе с Агатой); пол = кадр без Агаты, полоса у ступней (±260 px по x,
−10…+70 px по y). Печатает: яркость фигуры / яркость пола (Rec.709 по sRGB-значениям) и тёплый сдвиг
фигуры (R − B). Критерий Директора/координатора 17.10: в тёмной H1 отношение 0,85…1,15.

Запуск: python3 tools/measure_tone.py <папка кадров> <сценарий>:<x>:<y>[:x0,y0,x1,y1] [...]  [--check 0.85 1.15]
(x0,y0,x1,y1 — прямоугольник чистого пола рядом, когда у ступней мебель)
Код 1, если задан --check и хоть одно отношение вне границ.
Если рядом есть <имя>_neutral.png (тот же миг без тона комнаты), печатает насыщенность «пальто»
(тёмная половина фигуры) в тоне против нейтрального света; --sat-min 0.8 — порог (координатор 18.10:
тон комнаты не обесцвечивает актёров, ≥ 80 %).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def lum(a: np.ndarray) -> np.ndarray:
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def measure(folder: Path, name: str, x: int, y: int, floor_rect: list[int] | None = None) -> dict:
    a = np.asarray(Image.open(folder / f"{name}.png").convert("RGB")).astype(float)
    b = np.asarray(Image.open(folder / f"{name}_bg.png").convert("RGB")).astype(float)
    diff = np.abs(a - b).max(axis=2) > 14
    h, w = diff.shape
    fig = np.zeros_like(diff)
    fig[max(0, y - 700): max(0, y - 40), max(0, x - 260): min(w, x + 260)] = True
    fig &= diff
    floor = np.zeros_like(diff)
    if floor_rect:  # x0, y0, x1, y1 — clear floor by her when furniture stands around the feet
        floor[floor_rect[1]:floor_rect[3], floor_rect[0]:floor_rect[2]] = True
    else:
        floor[max(0, y - 10): min(h, y + 70), max(0, x - 260): min(w, x + 260)] = True
    if fig.sum() < 200:
        return {"name": name, "error": "фигура не найдена (%d px)" % int(fig.sum())}
    f_rgb = a[fig].mean(axis=0)
    p_rgb = b[floor].mean(axis=0)
    sat = None
    neutral_path = folder / f"{name}_neutral.png"
    if neutral_path.exists():
        # Coat = the darker half of the figure on neutral light (no shawl, hands, face); saturation
        # (max − min) / max per pixel, mean — toned frame against the same pixels on neutral light.
        n = np.asarray(Image.open(neutral_path).convert("RGB")).astype(float)
        nl = lum(n)
        coat = fig & (nl <= np.median(nl[fig]))
        def s_of(img):
            px = img[coat]
            mx = px.max(axis=1)
            return float(((mx - px.min(axis=1)) / np.maximum(mx, 1.0)).mean())
        sat = {"toned": s_of(a), "neutral": s_of(n), "ratio": s_of(a) / max(s_of(n), 1e-6),
               "coat_rgb": [round(float(v), 1) for v in a[coat].mean(axis=0)],
               "coat_rgb_neutral": [round(float(v), 1) for v in n[coat].mean(axis=0)]}
    return {
        "sat": sat,
        "name": name,
        "figure_px": int(fig.sum()),
        "figure_lum": float(lum(f_rgb)),
        "floor_lum": float(lum(p_rgb)),
        "ratio": float(lum(f_rgb) / max(lum(p_rgb), 1e-3)),
        "warm": float(f_rgb[0] - f_rgb[2]),
        "figure_rgb": [round(float(v), 1) for v in f_rgb],
        "floor_rgb": [round(float(v), 1) for v in p_rgb],
    }


def main() -> int:
    args = sys.argv[1:]
    check = None
    if "--check" in args:
        i = args.index("--check")
        check = (float(args[i + 1]), float(args[i + 2]))
        args = args[:i] + args[i + 3:]
    sat_min = None
    if "--sat-min" in args:
        i = args.index("--sat-min")
        sat_min = float(args[i + 1])
        args = args[:i] + args[i + 2:]
    folder = Path(args[0])
    bad = 0
    for spec in args[1:]:
        parts = spec.split(":")
        name, x, y = parts[0], int(parts[1]), int(parts[2])
        fr = [int(v) for v in parts[3].split(",")] if len(parts) > 3 else None
        r = measure(folder, name, x, y, fr)
        if "error" in r:
            print(f"{name}: {r['error']}")
            bad += 1
            continue
        ok = check is None or check[0] <= r["ratio"] <= check[1]
        bad += 0 if ok else 1
        print(f"{name}: фигура {r['figure_lum']:.1f} / пол {r['floor_lum']:.1f} = {r['ratio']:.2f}"
              f"{'' if check is None else (' OK' if ok else ' ВНЕ ' + str(check))}; тёплый сдвиг R−B {r['warm']:.1f};"
              f" фигура RGB {r['figure_rgb']}, пол RGB {r['floor_rgb']} ({r['figure_px']} px)")
        if r.get("sat"):
            sa = r["sat"]
            sat_ok = sat_min is None or sa["ratio"] >= sat_min
            bad += 0 if sat_ok else 1
            print(f"    насыщенность пальто {sa['toned']:.3f} против {sa['neutral']:.3f} на нейтральном свете = {sa['ratio']:.2f}"
                  f"{'' if sat_min is None else (' OK' if sat_ok else ' НИЖЕ ' + str(sat_min))}; пальто RGB {sa['coat_rgb']} (нейтр. {sa['coat_rgb_neutral']})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
