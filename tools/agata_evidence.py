#!/usr/bin/env python3
"""Агата: листы против живого 3D — склейка кадров game/tests/shots_agata_3d.gd в сравнительные GIF/MP4.

  python3 tools/agata_evidence.py <кадры> <выход>   (кадры: <case>_<mode>_<NNN>.png, mode = sprites | 3d)

Для каждого случая — кадр «слева листы, справа 3D» (короче — держит последний кадр), подписи сверху;
выход: <case>.gif (уменьшенный, для просмотра в чате/репозитории) и <case>.mp4 (H.264, полный размер),
плюс <case>_strip.jpg — 8 равномерных кадров обоих режимов (для отчёта). Кадры снимаются с --fixed-fps 30:
шаг между соседними кадрами последовательности известен (walk/startstop/stove — 2 кадра игры, idle — 3).
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
Image.MAX_IMAGE_PIXELS = None  # листы Агаты 2,25× (G56): сетка pick 34 560 × 6 912 px — свой файл, не «бомба»

STEP = {"walk": 2, "startstop": 2, "stove": 2, "idle": 3, "turn": 6}


def font(size: int):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def main() -> int:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    seqs: dict[str, dict[str, list[Path]]] = {}
    for p in sorted(src.glob("*_*_[0-9][0-9][0-9].png")):
        m = re.match(r"(.+)_(sprites|3d)_(\d{3})\.png$", p.name)
        if not m:
            continue
        seqs.setdefault(m.group(1), {}).setdefault(m.group(2), []).append(p)
    f_label = font(26)
    for case, modes in sorted(seqs.items()):
        a = modes.get("sprites", [])
        b = modes.get("3d", [])
        if not a or not b:
            continue
        n = max(len(a), len(b))
        w0, h0 = Image.open(a[0]).size
        kind = case.split("_")[0]
        step = STEP.get(kind, 2)
        fps = 30.0 / step if kind != "turn" else 3.0
        with tempfile.TemporaryDirectory() as td:
            frames = []
            for i in range(n):
                fa = Image.open(a[min(i, len(a) - 1)]).convert("RGB")
                fb = Image.open(b[min(i, len(b) - 1)]).convert("RGB")
                canvas = Image.new("RGB", (w0 * 2 + 8, h0 + 40), (24, 22, 20))
                canvas.paste(fa, (0, 40))
                canvas.paste(fb, (w0 + 8, 40))
                d = ImageDraw.Draw(canvas)
                d.text((12, 6), "листы (8 направлений)", fill=(230, 220, 200), font=f_label)
                d.text((w0 + 20, 6), "живое 3D", fill=(230, 220, 200), font=f_label)
                fp = Path(td) / f"f_{i:04d}.png"
                canvas.save(fp)
                frames.append(canvas)
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", f"{fps}", "-i", str(Path(td) / "f_%04d.png"),
                            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", str(out / f"{case}.mp4")], check=True)
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", f"{fps}", "-i", str(Path(td) / "f_%04d.png"),
                            "-vf", "scale=iw/3:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=160[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4",
                            str(out / f"{case}.gif")], check=True)
            k = 8
            idx = [round(i * (n - 1) / (k - 1)) for i in range(k)] if n > 1 else [0] * k
            sw, sh = w0 // 2, h0 // 2
            strip = Image.new("RGB", (sw * k, sh * 2 + 4), (24, 22, 20))
            for j, i in enumerate(idx):
                strip.paste(Image.open(a[min(i, len(a) - 1)]).convert("RGB").resize((sw, sh)), (j * sw, 0))
                strip.paste(Image.open(b[min(i, len(b) - 1)]).convert("RGB").resize((sw, sh)), (j * sw, sh + 4))
            strip.save(out / f"{case}_strip.jpg", quality=86)
        print(f"{case}: {len(a)} / {len(b)} кадров → {case}.gif, {case}.mp4, {case}_strip.jpg")
    return 0


if __name__ == "__main__":
    sys.exit(main())
