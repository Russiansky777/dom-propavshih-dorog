#!/usr/bin/env python3
"""Слои переднего плана (occluder: true) непрозрачны внутри (Директор 10.11: «Стул и Агата прозрачные, а должен быть
только один предмет на передней перспективе, а второй на фоне»).

Окклюдер рисуется поверх фигуры, которая за ним; если он полупрозрачный, фигура просвечивает — «оба прозрачные».
Так вышло у ночной спинки стула в горнице: её вырезали из ночной накидки O3/night.png, а она сама полупрозрачная
(в среднем 70 %; непрозрачных внутри силуэта — 13 %). Проверка: внутри силуэта слоя (силуэт, ужатый на ERODE точек — мягкий край не в счёт) непрозрачных
(альфа ≥ 250) не меньше OPAQUE_MIN.
Самопроверка (--self-check): тот же слой с альфой × 0,77 (как была ночная спинка) — пойман.

  python3 tools/validate_occluders.py [--self-check]   → код 0, если всё в порядке
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ERODE = 4
OPAQUE_MIN = 0.7   # мерка 10.11: у 28 окклюдеров игры 72–100 % (мягкие тени чашек и мела на столе — 72–75 %); ночная спинка стула до правки — 13 %


def interior_opaque(alpha: np.ndarray) -> float:
    """Доля непрозрачных точек внутри силуэта (силуэт — альфа > 0, ужатый на ERODE точек); 1.0 — внутри пусто."""
    sil = Image.fromarray(((alpha > 0) * 255).astype(np.uint8))
    inner = np.asarray(sil.filter(ImageFilter.MinFilter(2 * ERODE + 1))) > 0
    if inner.sum() == 0:
        return 1.0
    return float((alpha[inner] >= 250).mean())


def main() -> int:
    bad = 0
    n = 0
    sample = None
    for f in sorted(glob.glob(os.path.join(ROOT, "data/story/rooms/*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        for layer in d.get("layers", []):
            if not layer.get("occluder"):
                continue
            p = os.path.join(ROOT, "game", str(layer.get("image", "")).replace("res://", ""))
            if not os.path.exists(p):
                continue
            a = np.asarray(Image.open(p).convert("RGBA"))[:, :, 3]
            share = interior_opaque(a)
            n += 1
            if share < OPAQUE_MIN:
                print(f"FAIL  {d.get('id')}.{layer['id']}: внутри непрозрачно {share:.0%} (< {OPAQUE_MIN:.0%}) — фигура за ним просвечивает")
                bad += 1
            if sample is None and a.size and (a > 0).sum() > 20000:
                sample = (f"{d.get('id')}.{layer['id']}", a)
    if "--self-check" in sys.argv and sample is not None:
        faded = (sample[1].astype(np.float32) * 0.7686).astype(np.uint8)
        caught = interior_opaque(faded) < OPAQUE_MIN
        print(("OK    " if caught else "FAIL  ") + f"самопроверка: {sample[0]} с альфой × 0,77 " + ("пойман" if caught else "НЕ пойман"))
        bad += not caught
    print(f"окклюдеры: {n} слоёв, {bad} с ошибками")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
