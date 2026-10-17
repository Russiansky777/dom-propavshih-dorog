#!/usr/bin/env python3
"""Measures the stride drawn in a walk sheet: how far the SUPPORT foot shifts between consecutive
frames (the sheet keeps the body in place, so the planted foot slides backwards by exactly the
distance the body should cover per animation frame).

    python3 tools/measure_stride.py [--actor agata] [--check] [--strict] [--out build/reports]

Method: for the two profile rows (E and W) take the lowest 18 px of every frame, split the pixels
(alpha > 64) into connected components (feet), choose the lowest one (the support foot) and find
the horizontal shift that best overlaps it with the next frame's contact band. The median shift
is the stride per frame; × frames = the cycle in px; ÷ px-per-metre (frame_h / character_height_m
from sprites.json) = the cycle in metres that `walk.cycle_meters` in data/actors/<actor>.json must
match. The engine then moves the body by exactly that much per animation frame (player.gd:
fps = frames × speed_px / (cycle_meters × px_per_m)), so a correct sheet never slides.

Frames whose shift deviates from the median by more than --tolerance px are listed as sheet
defects: on those frames the foot skates on screen whatever the code does (regenerate the sheet).

--check  exits 1 when cycle_meters in the actor data disagrees with the measured cycle by > 8 %.
--strict additionally exits 1 when the sheet has defect frames.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

try:
    from scipy import ndimage
except ImportError:  # pragma: no cover
    ndimage = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def label(mask):
    if ndimage is not None:
        lab, n = ndimage.label(mask)
        return lab, n
    # Fallback: column-run labelling (good enough for feet, which never touch).
    lab = np.zeros(mask.shape, dtype=np.int32)
    n = 0
    cols = mask.any(axis=0)
    x = 0
    while x < mask.shape[1]:
        if cols[x]:
            n += 1
            while x < mask.shape[1] and cols[x]:
                lab[:, x] = np.where(mask[:, x], n, 0)
                x += 1
        else:
            x += 1
    return lab, n


def measure_row(alpha, row, fw, fh, frames, band_h=18, search=48):
    """Per-frame support-foot shift (px, signed on screen) for one direction row."""
    bands = []
    for i in range(frames):
        fr = alpha[row * fh:(row + 1) * fh, i * fw:(i + 1) * fw]
        ys = np.where(fr.any(axis=1))[0]
        if len(ys) == 0:
            bands.append(None)
            continue
        bottom = int(ys.max())
        band = fr[bottom - band_h + 1:bottom + 1, :]
        bands.append((bottom, band))
    out = []
    for i in range(frames):
        cur = bands[i]
        nxt = bands[(i + 1) % frames]
        if cur is None or nxt is None:
            out.append({"frame": i, "shift": None})
            continue
        bottom, band = cur
        lab, n = label(band)
        comps = []
        for k in range(1, n + 1):
            ys, xs = np.where(lab == k)
            if len(xs) < 30:
                continue
            comps.append({"ymax": int(ys.max()), "cx": float(xs.mean()), "x0": int(xs.min()), "x1": int(xs.max()), "mask": lab == k})
        if not comps:
            out.append({"frame": i, "shift": None})
            continue
        sup = max(comps, key=lambda c: (c["ymax"], -abs(c["cx"] - fw / 2)))
        best = None
        for dx in range(-search, search + 1):
            score = int((np.roll(sup["mask"], dx, axis=1) & nxt[1]).sum())
            if best is None or score > best[1]:
                best = (dx, score)
        out.append({"frame": i, "shift": best[0], "overlap": best[1], "support_x": [sup["x0"], sup["x1"]], "support_cx": round(sup["cx"], 1)})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--actor", default="agata")
    ap.add_argument("--sheet-dir", default=None, help="folder with walk.png + sprites.json (default assets/characters/<actor>)")
    ap.add_argument("--data", default=None, help="actor data json (default game/data/actors/<actor>.json)")
    ap.add_argument("--rows", default="2:1,6:-1", help="rows to measure as row:sign (sign = screen direction of travel: row 2 = E → +1, row 6 = W → -1)")
    ap.add_argument("--tolerance", type=float, default=6.0, help="px deviation from the median that counts as a defect frame")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "reports"))
    args = ap.parse_args()

    sheet_dir = args.sheet_dir or os.path.join(ROOT, "assets", "characters", args.actor)
    data_path = args.data or os.path.join(ROOT, "game", "data", "actors", f"{args.actor}.json")
    with open(os.path.join(sheet_dir, "sprites.json"), encoding="utf-8") as f:
        sprites = json.load(f)
    actor = {}
    if os.path.exists(data_path):
        with open(data_path, encoding="utf-8") as f:
            actor = json.load(f)
    walk_action = actor.get("walk_action", "walk")
    act = sprites["actions"][walk_action]
    fw, fh = int(sprites["frame_w"]), int(sprites["frame_h"])
    frames = int(act.get("frames", 12))
    height_m = float(sprites.get("character_height_m", 1.657))
    px_per_m = fh / height_m

    img = Image.open(os.path.join(sheet_dir, act.get("sheet", walk_action + ".png"))).convert("RGBA")
    alpha = np.array(img.split()[3]) > 64

    rows = []
    all_shifts = []
    defects = []
    for spec in args.rows.split(","):
        row, sign = spec.split(":")
        row, sign = int(row), int(sign)
        res = measure_row(alpha, row, fw, fh, frames)
        # Travel direction: the support foot slides against the motion → stride = -sign × shift.
        strides = [(-sign * r["shift"]) if r["shift"] is not None else None for r in res]
        valid = [s for s in strides if s is not None]
        med = float(np.median(valid)) if valid else 0.0
        bad = [r["frame"] for r, s in zip(res, strides) if s is None or abs(s - med) > args.tolerance]
        rows.append({"row": row, "sign": sign, "stride_per_frame": strides, "median": med, "defect_frames": bad})
        all_shifts += [s for s in valid if abs(s - med) <= args.tolerance]
        defects += [(row, b) for b in bad]

    stride = float(np.median(all_shifts)) if all_shifts else 0.0
    cycle_px = stride * frames
    cycle_m = cycle_px / px_per_m
    data_cycle = float(actor.get("walk", {}).get("cycle_meters", 0.0))
    report = {
        "actor": args.actor,
        "sheet": os.path.relpath(os.path.join(sheet_dir, act.get("sheet", walk_action + ".png")), ROOT),
        "frame": [fw, fh], "frames": frames,
        "character_height_m": height_m, "px_per_m_at_scale_1": round(px_per_m, 2),
        "stride_px_per_frame_median": round(stride, 2),
        "cycle_px": round(cycle_px, 1), "cycle_m_measured": round(cycle_m, 3),
        "cycle_m_in_data": data_cycle,
        "rows": rows,
        "defect_frames": [{"row": r, "frame": f} for r, f in defects],
        "tolerance_px": args.tolerance,
    }
    os.makedirs(args.out, exist_ok=True)
    out_path = os.path.join(args.out, f"stride_{args.actor}.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"sheet {report['sheet']}: {frames} frames × {fw}x{fh}, {height_m} m → {px_per_m:.1f} px/m at scale 1")
    for r in rows:
        print(f"  row {r['row']} (travel {'+x' if r['sign'] > 0 else '-x'}): stride per frame {r['stride_per_frame']}  median {r['median']:.1f}  defects {r['defect_frames']}")
    print(f"  stride {stride:.2f} px/frame → cycle {cycle_px:.0f} px = {cycle_m:.3f} m; data cycle_meters = {data_cycle}")
    print(f"  report: {os.path.relpath(out_path, ROOT)}")
    code = 0
    if args.check and data_cycle > 0 and abs(cycle_m - data_cycle) / data_cycle > 0.08:
        print(f"  FAIL cycle_meters in data ({data_cycle}) differs from the sheet ({cycle_m:.3f}) by more than 8 %")
        code = 1
    if defects:
        msg = f"{len(defects)} frame transition(s) deviate from the median stride by > {args.tolerance:.0f} px: the foot skates there (sheet defect, regenerate)"
        print(("  FAIL " if args.strict else "  WARN ") + msg)
        if args.strict:
            code = 1
    sys.exit(code)


if __name__ == "__main__":
    main()
