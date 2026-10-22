#!/usr/bin/env python3
"""Rope texture for code-drawn ropes (Director 23.10, F5: «канат … однородного цвета»).

Cuts the straight run of the drawn rope out of the plate close-up layer (closeup_plate_rope.png, art batch 3:
the rope tied on the ring, lower left of the canvas, ≈33° to the horizontal), straightens it along its axis
and makes it tile along its length: the strip is cut to a whole number of strand twists (period by
autocorrelation of the strip's brightness) and the seam is cross-faded. The game draws ropes with a
Line2D in tile mode with this texture (RopeLine.make): the strands, their highlights and the fibres come
from the painting, not a flat colour.

    python3 tools/make_rope_texture.py            # writes game/assets/closeups/rope_tile.png
    python3 tools/make_rope_texture.py --check    # verifies the file is up to date (exit 1 otherwise)
    python3 tools/make_rope_texture.py --preview  # also writes a preview strip to build/rope_preview.png
"""
from __future__ import annotations

import argparse
import io
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "game/assets/closeups/closeup_plate_rope.png"
DST = ROOT / "game/assets/closeups/rope_tile.png"
X_RANGE = (205, 368)      # columns where the rope runs straight and whole (not cut by the frame, before the knot)
OUT_H = 64                # texture height = the rope's thickness in the texture (Line2D width maps onto it)


def fit_axis(alpha: np.ndarray) -> tuple[float, float, float]:
    """Line y = a·x + b through the middle of the rope in X_RANGE, and the rope's thickness across it."""
    xs, mids, spans = [], [], []
    for x in range(*X_RANGE):
        ys = np.where(alpha[:, x] > 128)[0]
        if len(ys) == 0:
            continue
        xs.append(x)
        mids.append((ys.min() + ys.max()) / 2.0)
        spans.append(ys.max() - ys.min())
    a, b = np.polyfit(xs, mids, 1)
    thick = float(np.median(spans)) * math.cos(math.atan(a))
    return float(a), float(b), thick


def bilinear(img: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    p00 = img[y0, x0]
    p10 = img[y0, x0 + 1]
    p01 = img[y0 + 1, x0]
    p11 = img[y0 + 1, x0 + 1]
    return (p00 * (1 - fx) + p10 * fx) * (1 - fy) + (p01 * (1 - fx) + p11 * fx) * fy


def build() -> Image.Image:
    src = np.asarray(Image.open(SRC).convert("RGBA")).astype(np.float64)
    a, b, thick = fit_axis(src[:, :, 3])
    ang = math.atan(a)
    ux, uy = math.cos(ang), math.sin(ang)          # along the rope (to the right and up: a < 0)
    nx, ny = -uy, ux                               # across
    x0, x1 = X_RANGE
    p0 = np.array([x0, a * x0 + b])
    length = (x1 - x0) / math.cos(ang)
    half = thick * 0.56                            # a little margin: the fibres stand out of the rope
    n_s = int(round(length))
    n_t = int(round(half * 2))
    s = np.arange(n_s)[None, :].repeat(n_t, 0).astype(np.float64)
    t = (np.arange(n_t)[:, None].repeat(n_s, 1) - n_t / 2.0)
    px = p0[0] + s * ux + t * nx
    py = p0[1] + s * uy + t * ny
    strip = bilinear(src, px, py)                  # rows across the rope, columns along it
    # Period of the twist: autocorrelation of the mean brightness along the rope.
    lum = strip[:, :, :3].mean(axis=2) * (strip[:, :, 3] / 255.0)
    prof = lum[n_t // 4: 3 * n_t // 4].mean(axis=0)
    prof = prof - prof.mean()
    ac = np.correlate(prof, prof, mode="full")[len(prof) - 1:]
    lo = int(thick * 0.35)
    period = lo + int(np.argmax(ac[lo: len(prof) // 2]))
    whole = max(period * max(1, (n_s - period // 2) // period), period)
    tile = strip[:, :whole].copy()
    # Cross-fade the seam: the last `fade` columns blend into the columns before the first.
    fade = max(6, period // 3)
    extra = strip[:, whole: whole + fade] if whole + fade <= n_s else strip[:, -fade:]
    w = np.linspace(0.0, 1.0, fade)[None, :, None]
    tile[:, :fade] = tile[:, :fade] * w + extra * (1 - w)
    # The rope runs right-to-left-up in the painting: flip so the texture's u runs from the end to the knot
    # and the lit side (upper left in the painting) is on top.
    img = Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8), "RGBA")
    if ny > 0:
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    out_w = max(8, int(round(img.width * OUT_H / img.height)))
    img = img.resize((out_w, OUT_H), Image.LANCZOS)
    # Opaque core: the alpha of the painted rope's edges stays (soft fibres), the middle is fully opaque.
    arr = np.asarray(img).copy()
    core = slice(int(OUT_H * 0.2), int(OUT_H * 0.8))
    arr[core, :, 3] = 255
    print(f"rope axis slope {a:.3f} ({math.degrees(ang):.1f}°), thickness {thick:.1f} px, twist period {period} px, "
          f"tile {whole} px → {out_w}×{OUT_H}")
    return Image.fromarray(arr, "RGBA")


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    img = build()
    data = png_bytes(img)
    if args.check:
        if not DST.exists():
            print(f"missing {DST.relative_to(ROOT)}")
            return 1
        cur = np.asarray(Image.open(DST).convert("RGBA")).astype(int)
        new = np.asarray(img).astype(int)
        if cur.shape != new.shape or np.abs(cur - new).max() > 2:
            print(f"{DST.relative_to(ROOT)} is out of date — run tools/make_rope_texture.py")
            return 1
        print("rope_tile.png up to date")
        return 0
    DST.write_bytes(data)
    print(f"wrote {DST.relative_to(ROOT)}")
    if args.preview:
        prev = Image.new("RGBA", (img.width * 6, img.height), (40, 34, 28, 255))
        for i in range(6):
            prev.alpha_composite(img, (i * img.width, 0))
        (ROOT / "build").mkdir(exist_ok=True)
        prev.save(ROOT / "build/rope_preview.png")
        print("preview build/rope_preview.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
