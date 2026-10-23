#!/usr/bin/env python3
"""Слои партии H, нарисованные кодом (Pillow), полный холст 1672×941, ставятся в (0, 0):

  game/assets/rooms/O3/state_village_list.png — H40 (Директор 24.10: «список деревни на столе — не видно его»): лист
      списка лежит на столе горницы у зеркальца — бумага в перспективе стола, строки рукой (тонкие неровные штрихи),
      мягкая тень. Место — data/story/rooms/O3.json хотспот village_list.

Повторный запуск даёт те же файлы (свой генератор случайных чисел с зерном). Запуск: python3 tools/make_h_layers.py
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
W, H = 1672, 941


def paper_quad(quad, paper=(212, 192, 152), ink=(60, 44, 30), lines=7, seed=40) -> Image.Image:
    """Лист в перспективе: четырёхугольник quad (по часовой от левого верхнего), строки — штрихи от края до края."""
    rnd = random.Random(seed)
    big = 4
    sw, sh = 400, 520
    sheet = Image.new("RGBA", (sw, sh), paper + (255,))
    d = ImageDraw.Draw(sheet)
    for i in range(sh):                        # бумага чуть желтеет к краям
        k = abs(i / sh - 0.5) * 2
        d.line([(0, i), (sw, i)], fill=(int(paper[0] - 14 * k), int(paper[1] - 16 * k), int(paper[2] - 20 * k), 255))
    d.text((40, 30), "", fill=ink)
    y = 70
    for n in range(lines * 2):
        x = 40 + rnd.randint(0, 14)
        end = sw - 40 - rnd.randint(0, 120)
        pts = []
        while x < end:
            pts.append((x, y + rnd.uniform(-3, 3)))
            x += rnd.uniform(6, 14)
        d.line(pts, fill=ink + (200,), width=4)
        y += 30 if n % 2 else 26
        if y > sh - 50:
            break
    d.rectangle([0, 0, sw - 1, sh - 1], outline=(150, 128, 92, 255), width=3)
    # Перспектива: прямоугольник листа → quad на холсте (коэффициенты по 4 точкам).
    out = Image.new("RGBA", (W * big, H * big), (0, 0, 0, 0))
    q = [(x * big, y * big) for x, y in quad]
    coeffs = _persp(q, [(0, 0), (sw, 0), (sw, sh), (0, sh)])
    warped = sheet.transform(out.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + 3 * big, y + 3 * big) for x, y in q], fill=(20, 10, 4, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(3 * big))
    out.alpha_composite(shadow)
    out.alpha_composite(warped)
    return out.resize((W, H), Image.LANCZOS)


def _persp(dst, src):
    """Коэффициенты Image.PERSPECTIVE: точка вывода (dst) → точка исходника (src)."""
    import numpy as np
    a = []
    b = []
    for (x, y), (u, v) in zip(dst, src):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        b += [u, v]
    return list(np.linalg.solve(np.array(a, float), np.array(b, float)))


def main() -> int:
    o3 = paper_quad([(236, 513), (316, 509), (328, 533), (229, 538)])
    p = ROOT / "game" / "assets" / "rooms" / "O3" / "state_village_list.png"
    p.parent.mkdir(parents=True, exist_ok=True)
    o3.save(p, optimize=True)
    print(f"записан {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
