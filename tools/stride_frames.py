#!/usr/bin/env python3
"""Stance-foot drift on screen, from the stroboscope captured by
`SHOTS_MODE=stride node tools/screenshots.mjs` (build/shots/m1/stride/: ref.png, <label>_NN.png,
series.json — every capture is taken with the game paused, together with the sprite state).

For every pair of consecutive captures across exactly ONE walk-frame change (sheet frame k → k+1):
  * the figure's silhouette is the difference against ref.png (same room, figure elsewhere);
  * the feet are the blobs of the lowest band of the silhouette (feet side by side are split at the
    column gap); feet within a few px of the lowest pixel are "on the ground";
  * each ground foot is template-matched (RGB, 2D, sub-pixel) into the next capture;
  * the STANCE foot is the ground foot that moves most backward against the direction of travel
    (in an in-place walk clip the planted foot slides back; after compensation it should not move,
    while the swinging/landing foot moves forward) — the conservative choice;
  * its screen displacement is the drift: along the travel and across it.

Pairs inside one sheet frame must show no motion of the figure at all (foot lock between changes).

    python3 tools/stride_frames.py build/shots/m1/stride [--max-drift 6] [--strict] [--tag after]

Writes stride_report.txt/.json, stride_<label>.gif (fixed floor window) and stride_strip.jpg.
Exit code 1 on an engine violation (figure moved inside one sheet frame), or with --strict on any
stance-foot drift above --max-drift px.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None
try:
    from scipy import ndimage
except ImportError:  # pragma: no cover
    ndimage = None

N_FRAMES = 12


def silhouette(img, ref, box, thresh=38):
    """Figure pixels: difference against ref.png, or — when ref is a colour tuple (isolated
    measurement view, flat grey screen) — against that colour with a low threshold."""
    a = np.asarray(img.crop(box), dtype=np.int16)
    if isinstance(ref, tuple):
        b = np.array(ref, dtype=np.int16)[None, None, :]
        thresh = 10
    else:
        b = np.asarray(ref.crop(box), dtype=np.int16)
    d = np.abs(a - b).max(axis=2) > thresh
    if ndimage is not None:
        d = ndimage.binary_opening(d, iterations=1)
        d = ndimage.binary_closing(d, iterations=2)
    return d


def split_feet(mask, min_px):
    """Connected blobs of the band; a blob two feet wide with a column dip is split in two."""
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    blobs = []
    for i in range(1, n + 1):
        m = lab == i
        ys, xs = np.where(m)
        if len(xs) < min_px:
            continue
        x0, x1 = xs.min(), xs.max()
        prof = m[:, x0:x1 + 1].sum(axis=0).astype(float)
        w = x1 - x0 + 1
        cut = None
        if w > 12:
            lo, hi = int(w * 0.3), int(w * 0.7)
            if hi > lo:
                j = lo + int(np.argmin(prof[lo:hi]))
                if prof[j] < 0.35 * prof.max():
                    cut = x0 + j
        if cut is None:
            blobs.append(m)
        else:
            left = m.copy(); left[:, cut:] = False
            right = m.copy(); right[:, :cut] = False
            for part in (left, right):
                if part.sum() >= min_px:
                    blobs.append(part)
    return blobs


def match_2d(img_a, img_b, mask, origin, sx, sy):
    """Displacement (dx, dy) of the masked patch of img_a in img_b (sub-pixel), and the rms error."""
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    ox, oy = origin
    a = np.asarray(img_a, dtype=np.float32)
    b = np.asarray(img_b, dtype=np.float32)
    t = a[oy + y0:oy + y1 + 1, ox + x0:ox + x1 + 1]
    m = mask[y0:y1 + 1, x0:x1 + 1].astype(np.float32)
    X0, Y0 = max(0, ox + x0 - sx), max(0, oy + y0 - sy)
    X1, Y1 = min(b.shape[1], ox + x1 + 1 + sx), min(b.shape[0], oy + y1 + 1 + sy)
    reg = b[Y0:Y1, X0:X1]
    if reg.shape[0] < t.shape[0] or reg.shape[1] < t.shape[1]:
        return None
    res = cv2.matchTemplate(reg, t, cv2.TM_SQDIFF, mask=np.repeat(m[..., None], 3, axis=2)) / max(m.sum() * 3, 1)
    j = np.unravel_index(np.argmin(res), res.shape)

    def sub(v, i):
        if 0 < i < len(v) - 1:
            p, q, r = v[i - 1], v[i], v[i + 1]
            den = p - 2 * q + r
            return i + (0.5 * (p - r) / den if den > 1e-9 else 0.0)
        return float(i)
    yy = sub(res[:, j[1]], j[0])
    xx = sub(res[j[0], :], j[1])
    edge = j[0] in (0, res.shape[0] - 1) or j[1] in (0, res.shape[1] - 1)
    return X0 + xx - (ox + x0), Y0 + yy - (oy + y0), float(np.sqrt(res[j])), edge


def feet_of(img, ref, actor, vertical=False):
    sc = float(actor["scale"])
    dx, dy = float(actor["drawn_x"]), float(actor["drawn_y"])
    half = int(140 * sc)
    box = (max(0, int(dx - half)), max(0, int(dy - 70 * sc)), min(img.width, int(dx + half)), min(img.height, int(dy + 14 * sc)))
    sil = silhouette(img, ref, box)
    rows = np.where(sil.any(axis=1))[0]
    if len(rows) == 0:
        return box, None, []
    bottom = int(rows.max())
    band_h = int(round(22 * sc))
    band = np.zeros_like(sil)
    band[max(0, bottom - band_h + 1):bottom + 1] = sil[max(0, bottom - band_h + 1):bottom + 1]
    feet = []
    masks = split_feet(band, int(40 * sc * sc))
    if vertical:
        # Front/back views: the boots overlap; split the band at the figure's axis (left/right boot).
        axis = int(dx) - box[0]
        masks = []
        for side in (0, 1):
            m = band.copy()
            if side == 0:
                m[:, axis:] = False
            else:
                m[:, :axis] = False
            if m.sum() >= int(60 * sc * sc):  # a boot, not a sliver of heel or hem
                masks.append(m)
    for m in masks:
        ys, xs = np.where(m)
        feet.append({"mask": m, "x0": int(xs.min()), "x1": int(xs.max()), "y1": int(ys.max()), "cx": float(xs.mean())})
    return box, bottom, feet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--max-drift", type=float, default=6.0)
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    d = args.dir
    with open(os.path.join(d, "series.json"), encoding="utf-8") as f:
        series = json.load(f)
    ref_img = Image.open(os.path.join(d, "ref.png")).convert("RGB")
    isolated = set(series.get("isolated", []))
    labels = []
    for s in series["samples"]:
        if s["label"] not in labels:
            labels.append(s["label"])
    measured = [l for l in labels if not isolated or l in isolated]
    grey = None
    imgs = {}

    def load(s):
        if s["file"] not in imgs:
            im = Image.open(os.path.join(d, s["file"])).convert("RGB")
            clip = s.get("clip")
            if clip:  # band screenshot: paste back at its screen offset on a canvas of the band colour
                corner = im.getpixel((2, 2))
                full = Image.new("RGB", (1920, 1080), corner)
                full.paste(im, (int(clip["x"]), int(clip["y"])))
                im = full
            imgs[s["file"]] = im
            while len(imgs) > 6:  # small cache: the series is read pair by pair
                imgs.pop(next(iter(imgs)))
        return imgs[s["file"]]

    transitions = []
    engine_violations = []
    same_frame_pairs = 0
    for lab in measured:
        samples = [s for s in series["samples"] if s["label"] == lab and s["actor"].get("anim", "").startswith("walk_")]
        if lab in isolated and samples and grey is None:
            g = np.asarray(load(samples[0]), dtype=np.int16)
            border = np.concatenate([g[:20].reshape(-1, 3), g[-20:].reshape(-1, 3)])
            grey = tuple(int(v) for v in np.median(border, axis=0))
        ref = grey if lab in isolated else ref_img
        for a, b in zip(samples, samples[1:]):
            fa, fb = a["actor"]["frame"], b["actor"]["frame"]
            if a["actor"]["anim"] != b["actor"]["anim"]:
                continue
            ia, ib = load(a), load(b)
            if fa == fb:
                # Same sheet frame: nothing around the figure may change.
                box, _, _ = feet_of(ia, ref, a["actor"])
                pa = np.asarray(ia.crop(box), dtype=np.int16)
                pb = np.asarray(ib.crop(box), dtype=np.int16)
                changed = int((np.abs(pa - pb).max(axis=2) > 40).sum())
                same_frame_pairs += 1
                if changed > 50:
                    engine_violations.append(f"{lab}_{a['index']:02d}→{b['index']:02d}: same sheet frame {fa}, {changed} px changed")
                continue
            if (fb - fa) % N_FRAMES != 1:
                continue  # more than one frame change between captures: not a single transition
            mv = np.array([b["player"]["x"] - a["player"]["x"], b["player"]["y"] - a["player"]["y"]], dtype=float)
            if np.linalg.norm(mv) < 0.5:
                continue
            u = mv / np.linalg.norm(mv)
            sc = float(a["actor"]["scale"])
            vertical = abs(u[1]) > 0.8
            box, bottom, feet = feet_of(ia, ref, a["actor"], vertical)
            if bottom is None or not feet:
                continue
            cands = []
            for ft in feet:
                if ft["y1"] < bottom - (12 if vertical else 5) * sc:
                    continue  # lifted foot (front/back views: the far boot sits higher on screen)
                r = match_2d(ia, ib, ft["mask"], (box[0], box[1]), int(45 * sc), int(30 * sc))
                if r is None:
                    continue
                ddx, ddy, rms, edge = r
                if edge:
                    continue
                along = ddx * u[0] + ddy * u[1]
                perp = -ddx * u[1] + ddy * u[0]
                cands.append({"dx": ddx, "dy": ddy, "along": along, "perp": perp, "rms": rms, "x0": box[0] + ft["x0"], "x1": box[0] + ft["x1"], "y1": box[1] + ft["y1"]})
            if not cands:
                continue
            # A stance foot neither lifts nor jumps sideways: across-travel motion over 10 px × scale
            # means a foot leaving the ground (toe-off/swing), not the planted one.
            good = [c for c in cands if c["rms"] < 40 and abs(c["perp"]) <= 10 * sc]
            if not good:
                continue
            stance = min(good, key=lambda c: c["along"])  # most backward = worst planted-foot case
            others = [c for c in cands if c is not stance]
            transitions.append({
                "label": lab, "pair": [a["index"], b["index"]], "row": a["actor"].get("direction"),
                "from_frame": fa, "to_frame": fb, "scale": round(sc, 3),
                "drawn_step": round(float(np.hypot(b["actor"]["drawn_x"] - a["actor"]["drawn_x"], b["actor"]["drawn_y"] - a["actor"]["drawn_y"])), 1),
                "drift_along": round(stance["along"], 1), "drift_perp": round(stance["perp"], 1),
                "drift": round(float(np.hypot(stance["dx"], stance["dy"])), 1), "rms": round(stance["rms"], 1),
                "stance_x": [stance["x0"], stance["x1"]], "stance_y": stance["y1"],
                "other_feet_along": [round(c["along"], 1) for c in others],
            })

    # Per direction × transition summary (worst over repeats of the same transition).
    lines = []
    tag = f" [{args.tag}]" if args.tag else ""
    lines.append(f"stance-foot drift on screen{tag}: {len(transitions)} single-frame transitions, {same_frame_pairs} pairs inside one frame")
    worst = 0.0
    violations = []
    summary = {}
    for lab in measured:
        tr = [t for t in transitions if t["label"] == lab]
        if not tr:
            continue
        by = {}
        for t in tr:
            k = t["from_frame"]
            if k not in by or abs(t["drift"]) > abs(by[k]["drift"]):
                by[k] = t
        row = tr[0]["row"]
        cells = []
        for k in range(N_FRAMES):
            if k in by:
                cells.append(f"{by[k]['drift_along']:+5.1f}/{by[k]['drift_perp']:+4.1f}")
            else:
                cells.append("    —    ")
        lines.append(f"{lab:6s} (row {row}, scale ≈{tr[0]['scale']:.2f}); along/perp px per transition k→k+1, k = 0..11:")
        lines.append("   " + " ".join(f"{k:>2d}→{(k + 1) % N_FRAMES:<2d}     " for k in range(N_FRAMES)))
        lines.append("   " + "  ".join(cells))
        mx = max(abs(t["drift"]) for t in by.values())
        mx_along = max(abs(t["drift_along"]) for t in by.values())
        lines.append(f"   max |drift| {mx:.1f} px (along {mx_along:.1f}); transitions covered {len(by)}/12")
        summary[lab] = {"row": row, "covered": sorted(by.keys()), "max_drift": round(mx, 1), "max_along": round(mx_along, 1),
                        "per_transition": {str(k): {"along": by[k]["drift_along"], "perp": by[k]["drift_perp"], "drift": by[k]["drift"]} for k in sorted(by)}}
        worst = max(worst, mx)
        for k, t in sorted(by.items()):
            if abs(t["drift"]) > args.max_drift:
                violations.append(f"{lab} {k}→{(k + 1) % N_FRAMES}: stance foot moved {t['drift']:.1f} px (along {t['drift_along']:+.1f}, across {t['drift_perp']:+.1f})")
    lines.append(f"foot lock between frame changes: {same_frame_pairs} pairs, engine violations: {len(engine_violations)}")
    for v in engine_violations:
        lines.append("ENGINE " + v)
    lines.append(f"worst stance-foot drift: {worst:.1f} px (limit {args.max_drift:.0f})")
    for v in violations:
        lines.append("DRIFT " + v)
    text = "\n".join(lines) + "\n"
    print(text)
    with open(os.path.join(d, "stride_report.txt"), "w", encoding="utf-8") as f:
        f.write(text)
    with open(os.path.join(d, "stride_report.json"), "w", encoding="utf-8") as f:
        json.dump({"tag": args.tag, "max_drift": args.max_drift, "worst": worst, "violations": violations,
                   "engine_violations": engine_violations, "summary": summary, "transitions": transitions}, f, ensure_ascii=False, indent=2)

    # GIFs on a fixed floor window per label, and a contact strip of the transitions.
    strip = []
    for lab in labels:
        samples = [s for s in series["samples"] if s["label"] == lab and s["actor"].get("anim", "").startswith("walk_")]
        if not samples:
            continue
        xs = [s["actor"]["drawn_x"] for s in samples]
        ys = [s["actor"]["drawn_y"] for s in samples]
        sc = max(s["actor"]["scale"] for s in samples)
        win = (max(0, int(min(xs) - 150 * sc)), max(0, int(min(ys) - 400 * sc)), min(1920, int(max(xs) + 150 * sc)), min(1080, int(max(ys) + 30)))
        frames = []
        for s in samples:
            t = load(s).crop(win).copy()
            dr = ImageDraw.Draw(t)
            cap = f"{lab} {s['index']:02d} frame {s['actor']['frame']}"
            dr.rectangle([0, 0, 8 + 7 * len(cap), 16], fill=(0, 0, 0))
            dr.text((4, 2), cap, fill=(255, 255, 255))
            frames.append(t.resize((max(1, t.width // 2), max(1, t.height // 2))))
        frames[0].save(os.path.join(d, f"stride_{lab}.gif"), save_all=True, append_images=frames[1:], duration=67, loop=0)
        for t in [t for t in transitions if t["label"] == lab][:12]:
            a = next(s for s in samples if s["index"] == t["pair"][0])
            b = next(s for s in samples if s["index"] == t["pair"][1])
            cx, cy = int(np.mean(t["stance_x"])), int(t["stance_y"])
            bx = (cx - int(120 * sc), cy - int(90 * sc), cx + int(120 * sc), cy + int(20 * sc))
            pa, pb = load(a).crop(bx), load(b).crop(bx)
            tile = Image.new("RGB", (pa.width * 2, pa.height + 18), (20, 20, 20))
            tile.paste(pa, (0, 18)); tile.paste(pb, (pa.width, 18))
            dr = ImageDraw.Draw(tile)
            dr.line([(pa.width + (t["stance_x"][0] - bx[0]), 18), (pa.width + (t["stance_x"][0] - bx[0]), tile.height)], fill=(255, 220, 0))
            dr.line([(t["stance_x"][0] - bx[0], 18), (t["stance_x"][0] - bx[0], tile.height)], fill=(255, 220, 0))
            dr.text((4, 3), f"{lab} {t['from_frame']}→{t['to_frame']}: stance foot {t['drift_along']:+.1f}/{t['drift_perp']:+.1f} px", fill=(255, 255, 255))
            strip.append(tile.resize((tile.width // 2, tile.height // 2)))
    if strip:
        cols = 4
        tw = max(t.width for t in strip); th = max(t.height for t in strip)
        sheet = Image.new("RGB", (cols * tw, ((len(strip) + cols - 1) // cols) * th), (30, 30, 30))
        for i, t in enumerate(strip):
            sheet.paste(t, ((i % cols) * tw, (i // cols) * th))
        sheet.save(os.path.join(d, "stride_strip.jpg"), quality=85)
    bad = bool(engine_violations) or (args.strict and violations)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
