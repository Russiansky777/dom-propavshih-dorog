"""Без правки: картинка в игру как пришла (запись в таблице tools/retouch_art.py — чтобы --check сверял копию)."""
from __future__ import annotations

from PIL import Image


def retouch(im: Image.Image) -> Image.Image:
    return im.convert("RGBA")
