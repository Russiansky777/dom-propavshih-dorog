#!/usr/bin/env python3
"""Contact sheets for the AI sprite QA (tools/ai_checks/sprite_qa.mjs). Reads assets/characters/<name>/
(sprites.json + action sheets: rows = 8 directions, columns = frames) and writes JPEGs to --out:

  <name>_<action>.jpg   grid: columns = 8 directions d0..d7, rows = sampled frames, cropped to the figure, 1:1
  <name>_<action>_feet.jpg  (walk / idle) the lower part of every frame enlarged: boots, toes, hem
  <name>_views.jpg      the Meshy reference views (view_*.png) side by side
  lineup.jpg            (--lineup) every character's idle d0 and d2 at its height in metres, on one baseline

and a manifest JSON on stdout: [{"file", "name", "action", "kind", "caption"}]. Read-only for the assets.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CHARS = os.path.join(ROOT, "assets", "characters")
BG = (128, 128, 128)
MAX_EDGE = 2560          # Claude 4.7+: up to 2576 px on the long edge
MAX_TOKENS = 4700        # ... and 4784 visual tokens (28×28 patches)


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def fit(im):
    """Scale down so that the image stays within the long-edge and visual-token limits."""
    w, h = im.size
    s = min(1.0, MAX_EDGE / max(w, h))
    while ((w * s + 27) // 28) * ((h * s + 27) // 28) > MAX_TOKENS:
        s *= 0.95
    return im if s >= 0.999 else im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)


def on_bg(im):
    bg = Image.new("RGBA", im.size, BG + (255,))
    bg.alpha_composite(im.convert("RGBA"))
    return bg.convert("RGB")


def frames_of(sheet, fw, fh):
    cols, rows = sheet.size[0] // fw, sheet.size[1] // fh
    return cols, rows


def union_bbox(sheet, fw, fh, cols, rows):
    x0, y0, x1, y1 = fw, fh, 0, 0
    for r in range(rows):
        for c in range(cols):
            bb = sheet.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)).getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if bb:
                x0, y0, x1, y1 = min(x0, bb[0]), min(y0, bb[1]), max(x1, bb[2]), max(y1, bb[3])
    if x1 <= x0:
        return (0, 0, fw, fh)
    m = 6
    return (max(0, x0 - m), max(0, y0 - m), min(fw, x1 + m), min(fh, y1 + m))


def sample(n, k):
    if n <= k:
        return list(range(n))
    return sorted({round(i * (n - 1) / (k - 1)) for i in range(k)})


def grid(sheet, fw, fh, cols, rows, box, frames, scale, label_h=26):
    cw, ch = int((box[2] - box[0]) * scale), int((box[3] - box[1]) * scale)
    lw = 54
    out = Image.new("RGB", (lw + rows * cw, label_h + len(frames) * ch), BG)
    d = ImageDraw.Draw(out)
    f = font(18)
    for r in range(rows):
        d.text((lw + r * cw + 6, 4), f"d{r}", fill=(255, 255, 255), font=f)
    for i, c in enumerate(frames):
        d.text((6, label_h + i * ch + 6), f"f{c}", fill=(255, 255, 255), font=f)
        for r in range(rows):
            cell = sheet.crop((c * fw + box[0], r * fh + box[1], c * fw + box[2], r * fh + box[3]))
            cell = on_bg(cell)
            if scale != 1:
                cell = cell.resize((cw, ch), Image.LANCZOS)
            out.paste(cell, (lw + r * cw, label_h + i * ch))
        d.line([(lw, label_h + i * ch), (out.size[0], label_h + i * ch)], fill=(100, 100, 100))
    for r in range(1, rows):
        d.line([(lw + r * cw, label_h), (lw + r * cw, out.size[1])], fill=(100, 100, 100))
    return out


def character(name, out_dir):
    cdir = os.path.join(CHARS, name)
    meta = json.load(open(os.path.join(cdir, "sprites.json"), encoding="utf-8"))
    fw, fh = int(meta.get("frame_w", 288)), int(meta.get("frame_h", 384))
    items = []
    for action, spec in (meta.get("actions") or {}).items():
        p = os.path.join(cdir, spec.get("sheet", f"{action}.png"))
        if not os.path.exists(p):
            continue
        sheet = Image.open(p).convert("RGBA")
        cols, rows = frames_of(sheet, fw, fh)
        cols = min(cols, int(spec.get("frames", cols)))
        box = union_bbox(sheet, fw, fh, cols, rows)
        k = 6 if action == "walk" else (3 if action == "idle" else 5)
        fr = sample(cols, k)
        g = fit(grid(sheet, fw, fh, cols, rows, box, fr, 1.0))
        f = os.path.join(out_dir, f"{name}_{action}.jpg")
        g.save(f, quality=85)
        cols_txt = ("столбцы — строки листа позы (вид из зеркала горницы; у ходьбы d0 — влево, d1 — вправо)"
                    if meta.get("kind") == "mirror_poses" else "столбцы — направления d0..d7 (d0 анфас, дальше по часовой)")
        items.append({"file": f, "name": name, "action": action, "kind": "grid",
                      "caption": f"{name}, «{action}» ({spec.get('clip', '')}): {cols_txt}, строки — кадры {', '.join('f%d' % c for c in fr)} из {cols}"})
        if action in ("walk", "idle"):
            # Lower part of the figure: from 72 % of its height to the bottom, every frame of the walk / 3 of idle, enlarged.
            fy0 = box[1] + int((box[3] - box[1]) * 0.72)
            feet = (box[0], fy0, box[2], box[3])
            fr2 = list(range(cols)) if action == "walk" else sample(cols, 3)
            g2 = fit(grid(sheet, fw, fh, cols, rows, feet, fr2, 2.0))
            f2 = os.path.join(out_dir, f"{name}_{action}_feet.jpg")
            g2.save(f2, quality=88)
            items.append({"file": f2, "name": name, "action": action, "kind": "feet",
                          "caption": f"{name}, «{action}», низ фигуры ×2 (обувь, носки, подол): столбцы d0..d7, строки — кадры {', '.join('f%d' % c for c in fr2)}"})
    views = [os.path.join(cdir, v) for v in sorted(os.listdir(cdir)) if v.startswith("view_") and v.endswith(".png")]
    if views:
        ims = [on_bg(Image.open(v)) for v in views]
        h = max(i.size[1] for i in ims)
        out = Image.new("RGB", (sum(i.size[0] for i in ims) + 10 * (len(ims) - 1), h), BG)
        x = 0
        for i in ims:
            out.paste(i, (x, h - i.size[1]))
            x += i.size[0] + 10
        f = os.path.join(out_dir, f"{name}_views.jpg")
        fit(out).save(f, quality=85)
        items.append({"file": f, "name": name, "action": "views", "kind": "views",
                      "caption": f"{name}: опорные виды модели Meshy ({', '.join(os.path.basename(v) for v in views)})"})
    return items


def lineup(out_dir):
    px_per_m = 300
    ground = int(2.05 * px_per_m) + 30
    figs = []
    for name in sorted(os.listdir(CHARS)):
        cdir = os.path.join(CHARS, name)
        mp = os.path.join(cdir, "sprites.json")
        if not os.path.exists(mp):
            continue
        meta = json.load(open(mp, encoding="utf-8"))
        idle = (meta.get("actions") or {}).get("idle")
        if not idle or not os.path.exists(os.path.join(cdir, idle.get("sheet", "idle.png"))):
            continue
        fw, fh = int(meta.get("frame_w", 288)), int(meta.get("frame_h", 384))
        sheet = Image.open(os.path.join(cdir, idle.get("sheet", "idle.png"))).convert("RGBA")
        hm = float(meta.get("character_height_m") or 1.6)
        for d in (0, 2):
            fr = sheet.crop((0, d * fh, fw, (d + 1) * fh))
            bb = fr.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
            if not bb:
                continue
            fig = fr.crop(bb)
            s = hm * px_per_m / fig.size[1]
            figs.append((name, d, hm, fig.resize((max(1, int(fig.size[0] * s)), int(hm * px_per_m)), Image.LANCZOS)))
    if not figs:
        return []
    W = sum(f[3].size[0] + 40 for f in figs) + 80
    H = ground + 70
    out = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(out)
    f = font(20)
    for i in range(0, 9):
        y = ground - int(i * 0.25 * px_per_m)
        d.line([(0, y), (W, y)], fill=(150, 150, 150) if i % 4 else (200, 200, 200))
        d.text((4, y - 22), f"{i * 0.25:.2f} m", fill=(230, 230, 230), font=f)
    x = 80
    for name, dd, hm, im in figs:
        out.paste(im, (x, ground - im.size[1]), im)
        d.text((x, ground + 8), f"{name} d{dd}", fill=(255, 255, 255), font=f)
        d.text((x, ground + 34), f"{hm:.2f} m", fill=(255, 255, 255), font=f)
        x += im.size[0] + 40
    fpath = os.path.join(out_dir, "lineup.jpg")
    fit(out).save(fpath, quality=85)
    return [{"file": fpath, "name": "*", "action": "lineup", "kind": "lineup",
             "caption": "Все персонажи с листами idle: анфас (d0) и бок (d2), каждый в масштабе своего роста character_height_m из sprites.json, на общей линии пола; горизонтали — каждые 0,25 м"}]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--chars", default="")
    ap.add_argument("--lineup", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    items = []
    for n in [c for c in a.chars.split(",") if c]:
        if os.path.exists(os.path.join(CHARS, n, "sprites.json")):
            items += character(n, a.out)
    if a.lineup:
        items += lineup(a.out)
    json.dump(items, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
