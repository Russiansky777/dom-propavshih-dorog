#!/usr/bin/env python3
"""Р10 (Директор 29.10: нижняя улица убрана — «все упоминания»; сверка 30.10, 29.10 стр. 163): на слое плана партии 9
(zarechye_plan_overlay.png) от дома у дороги вниз уходил отрезок нижней улицы с вывеской. Этот скрипт стирает его
(мягкий край) в копии игры; tools/sync_map.sh вызывает его после каждого копирования слоя из assets/incoming, так что
результат всегда один и тот же. Новый слой от ChatGPT без нижней улицы — тогда скрипт не нужен.
Запуск: python3 tools/plan_overlay_r10.py [путь к png в игре]"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
P = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "game" / "assets" / "ui" / "map" / "zarechye_plan_overlay.png"
CUT = [(1098, 290), (1170, 280), (1172, 334), (1098, 334)]   # отрезок дороги вниз и вывеска (холст 1376×768)

im = Image.open(P).convert("RGBA")
m = Image.new("L", im.size, 0)
ImageDraw.Draw(m).polygon(CUT, fill=255)
k = np.asarray(m.filter(ImageFilter.GaussianBlur(4)), dtype=np.float32) / 255.0
a = np.asarray(im, dtype=np.float32).copy()
a[..., 3] *= 1.0 - k
Image.fromarray(a.astype(np.uint8), "RGBA").save(P, optimize=True)
print(f"{P.name}: нижняя улица стёрта (Р10)")
