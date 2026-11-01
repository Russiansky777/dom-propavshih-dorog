"""Слой плана Заречья: канат через реку с лодкой — те самые пиксели, что tools/retouch/zarechye_plan.py убрал с основы.
В игре виден с rope_on_ring (канат завязан на кольце плиты, M15) — data/story/map_zarechye.json, overlays."""
from __future__ import annotations

import importlib.util
from pathlib import Path

from PIL import Image, ImageFilter

_spec = importlib.util.spec_from_file_location("zarechye_plan_base", Path(__file__).with_name("zarechye_plan.py"))
_base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_base)


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    a = _base.rope_mask(im).filter(ImageFilter.GaussianBlur(1.0))
    out = im.copy()
    out.putalpha(a)
    return out
