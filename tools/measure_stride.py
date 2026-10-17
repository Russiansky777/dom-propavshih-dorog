#!/usr/bin/env python3
"""Root motion of a walk sheet from its planted (stance) foot → `walk.stride_table` in the actor data.

    python3 tools/measure_stride.py [--actor agata] [--write] [--check]

The walk clip is rendered in place: while a foot is planted it slides backward by exactly the
distance the body should cover. For every direction row and every transition k → k+1 the stance
foot is found and tracked (2D template match of the boot, RGB+alpha, sub-pixel):
  * candidates: feet (blobs of the lowest 22 px, split at a column gap when side by side) that touch
    the ground (≤ 5 px above the lowest pixel) in frame k and still do after the match in frame k+1;
  * the stance foot is the candidate sliding most backward against the row's direction of travel.

Ground profile g_k (px of the sheet at scale 1, per transition) comes from the two profile rows
(E and W — the feet are separated and the motion is in the image plane); they agree within a few px
where both are clean. Missing, negative or outlying values (outside [0.3·med, 1.7·med]) are filled
by cyclic interpolation from their neighbours. One cycle L = Σ g_k; cycle_meters = L / px_per_m.

All eight rows are views of the same clip from an orthographic camera at `camera_elev_deg` above
the horizon (pipeline/render/render_sprites.py --elev 14): a ground step of length g in the row's
direction φ appears on screen as g·|(cos φ, sin φ · sin elev)|. So row r gets
table[r][k] = g_k · proj_r — its own values (front/back rows ≈ 0.24·g, diagonals ≈ 0.73·g, profile g),
and the row's cycle on screen is L·proj_r. Every row is also measured directly; the report compares.

start_frame: the frame a walk starts on, chosen so that the drawn figure (which advances by the table
at each frame change) never runs ahead of the logical position (which advances at the cycle's mean
speed): the frame where the cumulative deviation Σ(g_i − L/N) is largest.

--write updates game/data/actors/<actor>.json (walk.stride_table, walk.cycle_meters).
--check exits 1 when the data's table is stale (sheet md5 or values differ from a fresh measurement).
Report: build/reports/stride_<actor>.json and stdout (before = constant stride, after = table).
"""
import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np
from PIL import Image

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOT_H = 22


def frame(img, r, k, fw, fh):
    return img[r * fh:(r + 1) * fh, k * fw:(k + 1) * fw]


def split_feet(mask, min_px=50):
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    out = []
    for i in range(1, n + 1):
        m = lab == i
        ys, xs = np.where(m)
        if len(xs) < min_px:
            continue
        x0, x1 = xs.min(), xs.max()
        prof = m[:, x0:x1 + 1].sum(axis=0).astype(float)
        w = x1 - x0 + 1
        cut = None
        if w > 50:
            lo, hi = int(w * 0.3), int(w * 0.7)
            j = lo + int(np.argmin(prof[lo:hi]))
            if prof[j] < 0.35 * prof.max():
                cut = x0 + j
        parts = [m] if cut is None else [np.where(np.arange(m.shape[1])[None, :] < cut, m, False),
                                         np.where(np.arange(m.shape[1])[None, :] >= cut, m, False)]
        for p in parts:
            if p.sum() >= min_px:
                out.append(p)
    return out


def feet(fr):
    a = fr[..., 3] > 64
    ys = np.where(a.any(axis=1))[0]
    bottom = int(ys.max())
    band = np.zeros_like(a)
    band[bottom - BOOT_H + 1:bottom + 1] = a[bottom - BOOT_H + 1:bottom + 1]
    res = []
    for m in split_feet(band):
        yy, xx = np.where(m)
        res.append({"mask": m, "x0": int(xx.min()), "x1": int(xx.max()), "y0": int(yy.min()), "y1": int(yy.max())})
    return bottom, res


def feat(fr):
    a = fr[..., 3:4] / 255.0
    return np.concatenate([fr[..., :3] * a, fr[..., 3:4]], axis=2).astype(np.float32)


def track(fr0, ft, fr1, sx=60, sy=16):
    x0, x1, y0, y1 = ft["x0"], ft["x1"], ft["y0"], ft["y1"]
    m = ft["mask"][y0:y1 + 1, x0:x1 + 1].astype(np.float32)
    t = feat(fr0)[y0:y1 + 1, x0:x1 + 1]
    f1 = feat(fr1)
    H, W = f1.shape[:2]
    X0, Y0 = max(0, x0 - sx), max(0, y0 - sy)
    X1, Y1 = min(W, x1 + 1 + sx), min(H, y1 + 1 + sy)
    res = cv2.matchTemplate(f1[Y0:Y1, X0:X1], t, cv2.TM_SQDIFF, mask=np.repeat(m[..., None], 4, axis=2)) / max(m.sum(), 1)
    j = np.unravel_index(np.argmin(res), res.shape)

    def sub(v, i):
        if 0 < i < len(v) - 1:
            p, q, r = v[i - 1], v[i], v[i + 1]
            den = p - 2 * q + r
            return i + (0.5 * (p - r) / den if den > 1e-9 else 0.0)
        return float(i)
    edge = j[0] in (0, res.shape[0] - 1) or j[1] in (0, res.shape[1] - 1)
    return X0 + sub(res[j[0], :], j[1]) - x0, Y0 + sub(res[:, j[1]], j[0]) - y0, float(np.sqrt(res[j])), edge


def row_geometry(r, directions, elev_deg):
    """Screen axis (unit) and projection factor of row r: row 0 faces the viewer (screen down),
    rows go counter-clockwise on screen (data: direction_zero down, direction_order ccw)."""
    phi = math.radians(90.0 - 360.0 / directions * r)
    p = np.array([math.cos(phi), math.sin(phi) * math.sin(math.radians(elev_deg))])
    n = float(np.linalg.norm(p))
    return p / n, n


def measure_row(img, r, frames, fw, fh, axis, max_rms=200.0):
    """Per transition: stance-foot backward slide along the row's axis (sheet px), or None."""
    out = []
    for k in range(frames):
        f0, f1 = frame(img, r, k, fw, fh), frame(img, r, (k + 1) % frames, fw, fh)
        b0, c0 = feet(f0)
        b1, _ = feet(f1)
        cands = []
        for ft in c0:
            if ft["y1"] < b0 - 5:
                continue
            dx, dy, rms, edge = track(f0, ft, f1)
            if edge or rms > max_rms or ft["y1"] + dy < b1 - 12:  # toe-off may lift the heel; a swing foot rises more
                continue
            back = -(dx * axis[0] + dy * axis[1])
            cands.append({"back": back, "dx": dx, "dy": dy, "rms": rms})
        if not cands:
            out.append(None)
        else:
            out.append(max(cands, key=lambda c: c["back"]))
    return out


def cyclic_fill(vals):
    v = np.array([np.nan if x is None else x for x in vals], dtype=float)
    n = len(v)
    ok = np.where(~np.isnan(v))[0]
    if len(ok) == 0:
        return v, []
    filled = []
    for i in range(n):
        if np.isnan(v[i]):
            prev = max([j for j in ok if j < i], default=ok[-1] - n)
            nxt = min([j for j in ok if j > i], default=ok[0] + n)
            t = (i - prev) / (nxt - prev)
            v[i] = v[prev % n] * (1 - t) + v[nxt % n] * t
            filled.append(i)
    return v, filled


def compact_json(obj):
    """indent=2, but arrays of numbers stay on one line (the table is 8 × 12 numbers)."""
    import re
    text = json.dumps(obj, ensure_ascii=False, indent=2)
    return re.sub(r"\[\s*(-?[0-9.eE+-]+(?:,\s*-?[0-9.eE+-]+)*)\s*\]",
                  lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]", text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--actor", default="agata")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--agree", type=float, default=4.0, help="px: profile rows E and W agree when within this")
    args = ap.parse_args()

    data_path = os.path.join(ROOT, "game", "data", "actors", f"{args.actor}.json")
    with open(data_path, encoding="utf-8") as f:
        actor = json.load(f)
    sheet_dir = os.path.join(ROOT, "game", actor.get("sheet_dir", f"res://assets/characters/{args.actor}").replace("res://", ""))
    with open(os.path.join(sheet_dir, actor.get("sprites", "sprites.json")), encoding="utf-8") as f:
        sprites = json.load(f)
    walk = actor.setdefault("walk", {})
    walk_action = actor.get("walk_action", "walk")
    act = sprites["actions"][walk_action]
    sheet_path = os.path.join(sheet_dir, act.get("sheet", walk_action + ".png"))
    with open(sheet_path, "rb") as f:
        md5 = hashlib.md5(f.read()).hexdigest()
    fw, fh = int(sprites["frame_w"]), int(sprites["frame_h"])
    N = int(act.get("frames", 12))
    dirs = int(sprites.get("directions", 8))
    px_per_m = fh / float(sprites.get("character_height_m", 1.657))
    elev = float(walk.get("camera_elev_deg", 14.0))
    img = np.array(Image.open(sheet_path).convert("RGBA")).astype(np.float32)

    geo = [row_geometry(r, dirs, elev) for r in range(dirs)]
    measured = [measure_row(img, r, N, fw, fh, geo[r][0]) for r in range(dirs)]
    profile = [r for r in range(dirs) if geo[r][1] > 0.99]  # E and W

    # Ground profile from the profile rows.
    g = []
    for k in range(N):
        vals = [measured[r][k]["back"] for r in profile if measured[r][k] is not None]
        if len(vals) == 2 and abs(vals[0] - vals[1]) <= args.agree:
            g.append(sum(vals) / 2)
        elif len(vals) == 2:
            # Disagreement: the row with the cleaner match wins.
            best = min((measured[r][k] for r in profile), key=lambda c: c["rms"])
            g.append(best["back"])
        elif len(vals) == 1:
            g.append(vals[0])
        else:
            g.append(None)
    med = float(np.median([x for x in g if x is not None]))
    cleaned = [x if (x is not None and 0.3 * med <= x <= 1.7 * med) else None for x in g]
    gv, filled = cyclic_fill(cleaned)
    L = float(gv.sum())
    dev = np.concatenate([[0.0], np.cumsum(gv - L / N)])[:N]
    start = int(np.argmax(dev))
    rows_table = [[round(float(x * geo[r][1]), 2) for x in gv] for r in range(dirs)]

    # Report.
    old_const = float(walk.get("sheet_stride_px_per_frame", 26.0))
    print(f"sheet {os.path.relpath(sheet_path, ROOT)} (md5 {md5[:10]}…): {N} frames × {dirs} rows, {fw}x{fh}, "
          f"{px_per_m:.1f} px/m at scale 1, render camera elev {elev:.0f}°")
    print("transition k→k+1:      " + " ".join(f"{k:>2d}→{(k + 1) % N:<2d}" for k in range(N)))
    for r in profile:
        cells = [f"{c['back']:6.1f}" if c else "     —" for c in measured[r]]
        print(f"row {r} measured (E/W): " + " ".join(cells))
    print("ground profile g_k:    " + " ".join(f"{x:6.1f}" for x in gv) + (f"   (filled: {filled})" if filled else ""))
    print(f"cycle L = {L:.1f} px = {L / px_per_m:.3f} m (data had cycle_meters {walk.get('cycle_meters')}); start_frame {start}")
    report_rows = []
    for r in range(dirs):
        meas = measured[r]
        diffs = [abs(c["back"] - rows_table[r][k]) for k, c in enumerate(meas) if c is not None]
        report_rows.append({"row": r, "proj": round(geo[r][1], 4), "axis": [round(float(v), 4) for v in geo[r][0]],
                            "table": rows_table[r], "cycle_px": round(L * geo[r][1], 2),
                            "measured": [None if c is None else round(c["back"], 2) for c in meas],
                            "max_abs_diff_measured_vs_table": round(max(diffs), 2) if diffs else None,
                            "measured_transitions": len(diffs)})
        cells = [f"{c['back']:6.1f}" if c else "     —" for c in meas]
        print(f"row {r} (proj {geo[r][1]:.3f}) table: " + " ".join(f"{x:6.1f}" for x in rows_table[r]))
        print(f"        measured:          " + " ".join(cells) + (f"   max |diff| {max(diffs):.1f} over {len(diffs)}" if diffs else ""))
    print("before (constant stride {:.1f}) vs after (table), |stance slide residual| on the profile rows, sheet px:".format(old_const))
    for r in profile:
        bef = [abs(c["back"] - old_const) if c else None for c in measured[r]]
        aft = [abs(c["back"] - rows_table[r][k]) if c else None for k, c in enumerate(measured[r])]
        print(f"  row {r} before: " + " ".join(f"{x:5.1f}" if x is not None else "    —" for x in bef) + f"   max {max(x for x in bef if x is not None):.1f}")
        print(f"  row {r} after:  " + " ".join(f"{x:5.1f}" if x is not None else "    —" for x in aft) + f"   max {max(x for x in aft if x is not None):.1f}")

    table = {
        "_comment": "Root motion по опорной ноге (tools/measure_stride.py): rows[r][k] — на сколько px листа (scale 1) опорная ступня строки r уезжает назад между кадрами k и k+1; нарисованная фигура при смене кадра продвигается ровно на rows[r][k] × scale вдоль пути. Профильные строки 2/6 измерены (профиль g_k), остальные — тот же клип в проекции ортокамеры рендера (elev): × |(cos φ, sin φ·sin elev)|. Логическая скорость строки = row_cycle_px × scale × fps / frames, fps = frames × speed_mps / cycle_meters. Перемерить после любой замены walk.png: python3 tools/measure_stride.py --write.",
        "sheet": os.path.relpath(sheet_path, os.path.join(ROOT, "game")).replace(os.sep, "/"),
        "sheet_md5": md5,
        "frames": N,
        "camera_elev_deg": elev,
        "ground_px": [round(float(x), 2) for x in gv],
        "cycle_px": round(L, 2),
        "row_cycle_px": [round(L * geo[r][1], 2) for r in range(dirs)],
        "start_frame": start,
        "rows": rows_table,
    }
    os.makedirs(os.path.join(ROOT, "build", "reports"), exist_ok=True)
    with open(os.path.join(ROOT, "build", "reports", f"stride_{args.actor}.json"), "w", encoding="utf-8") as f:
        json.dump({"table": table, "rows": report_rows, "ground_raw": [None if x is None else round(x, 2) for x in g],
                   "filled": filled, "old_constant_stride": old_const}, f, ensure_ascii=False, indent=2)

    code = 0
    if args.check:
        cur = walk.get("stride_table", {})
        stale = cur.get("sheet_md5") != md5
        if not stale:
            for r in range(dirs):
                for k in range(N):
                    if abs(float(cur.get("rows", [[0] * N] * dirs)[r][k]) - rows_table[r][k]) > 0.5:
                        stale = True
        print(("FAIL" if stale else "OK") + f" stride_table in {os.path.relpath(data_path, ROOT)} " + ("is stale — run with --write" if stale else "matches the sheet"))
        code = 1 if stale else 0
    if args.write:
        walk["cycle_meters"] = round(L / px_per_m, 4)
        walk.pop("sheet_stride_px_per_frame", None)
        walk["camera_elev_deg"] = elev
        walk["stride_table"] = table
        with open(data_path, "w", encoding="utf-8") as f:
            f.write(compact_json(actor) + "\n")
        print(f"written: {os.path.relpath(data_path, ROOT)} (walk.stride_table, cycle_meters {walk['cycle_meters']})")
    sys.exit(code)


if __name__ == "__main__":
    main()
