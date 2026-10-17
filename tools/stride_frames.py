#!/usr/bin/env python3
"""Analyses the stride frame series captured by `SHOTS_MODE=stride node tools/screenshots.mjs`
(build/shots/m1/stride/: ref.png, <label>_NN.png, series.json).

For every frame the figure's silhouette near the floor is taken as the difference against the
reference frame (same room, figure elsewhere). The lowest connected blob of the contact band is the
planted (support) foot; its screen x is tracked from frame to frame. While the same foot stays
planted its x must not move: that is the «ступня едет» check. Output:

  <dir>/stride_report.json / stride_report.txt  — per-frame numbers (sheet frame, drawn x, foot x, drift)
  <dir>/stride_<label>.gif                       — the series on a fixed floor window (half size)
  <dir>/stride_strip.jpg                         — contact sheet: tiles with the planted foot marked
                                                   (red = this frame, yellow = previous frame)

    python3 tools/stride_frames.py build/shots/m1/stride [--max-drift 6]

Two checks: (engine) captures inside one sheet frame must be pixel-identical around the figure —
the foot lock holds the drawn figure still; (sheet) across a frame change the planted foot must not
move more than --max-drift px — any remainder is the walk clip's own foot slide. Exit code 1 on an
engine violation (or on a sheet violation with --strict).
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

try:
    from scipy import ndimage
except ImportError:  # pragma: no cover
    ndimage = None


def label_mask(mask):
    if ndimage is not None:
        return ndimage.label(mask)
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


def silhouette(frame, ref, box, thresh=40):
    x0, y0, x1, y1 = box
    a = np.asarray(frame.crop(box).convert("RGB"), dtype=np.int16)
    b = np.asarray(ref.crop(box).convert("RGB"), dtype=np.int16)
    d = np.abs(a - b).max(axis=2) > thresh
    if ndimage is not None:
        d = ndimage.binary_opening(d, iterations=1)
    return d


def support_foot(mask, band_h=14, min_px=40):
    """Lowest blob of the contact band → (x0, x1, cx, ymax) in mask coords, or None."""
    rows = np.where(mask.any(axis=1))[0]
    if len(rows) == 0:
        return None
    bottom = int(rows.max())
    band = np.zeros_like(mask)
    band[bottom - band_h + 1:bottom + 1, :] = mask[bottom - band_h + 1:bottom + 1, :]
    lab, n = label_mask(band)
    comps = []
    for k in range(1, n + 1):
        ys, xs = np.where(lab == k)
        if len(xs) < min_px:
            continue
        comps.append((int(ys.max()), int(xs.min()), int(xs.max()), float(xs.mean())))
    if not comps:
        return None
    ymax, x0, x1, cx = max(comps, key=lambda c: (c[0], -(c[2] - c[1])))
    return {"x0": x0, "x1": x1, "cx": cx, "ymax": ymax, "bottom": bottom}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--max-drift", type=float, default=6.0)
    ap.add_argument("--strict", action="store_true", help="also fail on sheet-caused foot drift")
    ap.add_argument("--swap-px", type=int, default=40, help="search range for the planted foot; no match within it = foot swap")
    args = ap.parse_args()
    d = args.dir
    with open(os.path.join(d, "series.json"), encoding="utf-8") as f:
        series = json.load(f)
    ref = Image.open(os.path.join(d, "ref.png")).convert("RGB")
    stride = float(series.get("stride_px") or 0.0)

    results = []
    labels = []
    for s in series["samples"]:
        if s["label"] not in labels:
            labels.append(s["label"])
    report_lines = []
    worst = 0.0
    violations = []          # planted foot moved between two sheet frames (sheet consistency)
    engine_violations = []   # figure moved while the same sheet frame was shown (foot lock)
    tiles = {}
    for lab in labels:
        samples = [s for s in series["samples"] if s["label"] == lab and s["actor"].get("anim", "").startswith("walk_")]
        prev = None
        for s in samples:
            img = Image.open(os.path.join(d, s["file"])).convert("RGB")
            a = s["actor"]
            sc = float(a["scale"])
            dx, dy = float(a["drawn_x"]), float(a["drawn_y"])
            half = int(150 * sc)
            box = (max(0, int(dx - half)), max(0, int(dy - 120 * sc)), min(img.width, int(dx + half)), min(img.height, int(dy + 12)))
            mask = silhouette(img, ref, box)
            foot = support_foot(mask)
            entry = {"label": lab, "index": s["index"], "file": s["file"], "frame": a["frame"], "anim": a["anim"],
                     "speed_scale": round(float(a["speed_scale"]), 3), "scale": round(sc, 3),
                     "x_logical": round(float(s["player"]["x"]), 1), "x_drawn": round(dx, 1),
                     "walk_time": a.get("walk_time")}
            if foot:
                fx0, fx1 = box[0] + foot["x0"], box[0] + foot["x1"]
                entry.update({"foot_x0": fx0, "foot_x1": fx1, "foot_cx": round(box[0] + foot["cx"], 1), "foot_y": box[1] + foot["bottom"]})
            if prev is not None:
                if a["frame"] == prev["frame"] and prev.get("_img") is not None:
                    # Same sheet frame: the figure must not have moved at all (engine check).
                    pa = np.asarray(prev["_img"].crop(box).convert("RGB"), dtype=np.int16)
                    ca = np.asarray(img.crop(box).convert("RGB"), dtype=np.int16)
                    changed = int((np.abs(pa - ca).max(axis=2) > 40).sum())
                    entry["same_frame_changed_px"] = changed
                    if changed > 50:
                        engine_violations.append(f"{lab}_{s['index']:02d}: same sheet frame {a['frame']} but {changed} px changed around the figure")
                entry["d_drawn"] = round(dx - prev["x_drawn"], 1)
                entry["d_logical"] = round(entry["x_logical"] - prev["x_logical"], 1)
                entry["d_frames"] = (a["frame"] - prev["frame"]) % 12
                if a.get("walk_time") is not None and prev.get("walk_time") is not None:
                    entry["dt_ms"] = round((float(a["walk_time"]) - float(prev["walk_time"])) * 1000.0)
                if foot and prev.get("_band") is not None:
                    # Template match: where did the previously planted foot go? (search ±search px)
                    tmpl, tx0, ty0 = prev["_band"]
                    # The sheet's frames bottom out at slightly different rows: search the lowest
                    # 30 rows of the current silhouette, ±14 px vertically.
                    band_cur = np.zeros_like(mask)
                    band_cur[foot["bottom"] - 29:foot["bottom"] + 1, :] = mask[foot["bottom"] - 29:foot["bottom"] + 1, :]
                    best = None
                    area = int(tmpl.sum())
                    for ddx in range(-args.swap_px, args.swap_px + 1):
                        for ddy in range(-14, 15):
                            sx0 = tx0 + ddx - box[0]
                            sy0 = ty0 + ddy - box[1]
                            if sx0 < 0 or sy0 < 0 or sx0 + tmpl.shape[1] > band_cur.shape[1] or sy0 + tmpl.shape[0] > band_cur.shape[0]:
                                continue
                            score = int((tmpl & band_cur[sy0:sy0 + tmpl.shape[0], sx0:sx0 + tmpl.shape[1]]).sum())
                            # Ties (a band wider than the template) resolve to the smallest shift.
                            if best is None or score > best[1] or (score == best[1] and abs(ddx) + abs(ddy) < abs(best[0]) + abs(best[2])):
                                best = (ddx, score, ddy)
                    if best is not None and area > 0 and best[1] / area >= 0.55:
                        entry["drift"] = best[0]
                        entry["match"] = round(best[1] / area, 2)
                        worst = max(worst, abs(best[0]))
                        if abs(best[0]) > args.max_drift:
                            violations.append(f"{lab}_{s['index']:02d}: planted foot moved {best[0]:+d} px (sheet frame {prev['frame']}→{a['frame']})")
                    else:
                        entry["swap"] = True
                        entry["match"] = round(best[1] / area, 2) if (best and area) else 0.0
            entry["_img"] = img
            if foot:
                # Keep the planted foot's band (absolute coords) as the template for the next frame.
                fx0, fx1 = foot["x0"], foot["x1"]
                tmpl = mask[foot["bottom"] - 13:foot["bottom"] + 1, fx0:fx1 + 1].copy()
                entry["_band"] = (tmpl, box[0] + fx0, box[1] + foot["bottom"] - 13)
            results.append(entry)
            tiles.setdefault(lab, []).append((img, entry, prev))
            prev = entry

    # Text report
    report_lines.append(f"stride series: {len(results)} walking frames, stride at this depth = {stride:.1f} px, max allowed drift {args.max_drift:.0f} px")
    report_lines.append("label_idx  sheet_frame  dt_ms  d_logical  d_drawn  planted_foot_x  planted foot vs previous frame")
    for e in results:
        tag = ""
        if "drift" in e:
            tag = f"drift {e['drift']:+d} px (match {e['match']:.2f})"
        elif e.get("swap"):
            tag = f"foot swap (match {e.get('match', 0):.2f})"
        foot = f"{e['foot_x0']}..{e['foot_x1']}" if "foot_x0" in e else "-"
        report_lines.append(f"{e['label']}_{e['index']:02d}   f{e['frame']:2d}          {str(e.get('dt_ms', '-')):>4}   {e.get('d_logical', 0):+7.1f}   {e.get('d_drawn', 0):+7.1f}   {foot:>10}   {tag}")
    same = [e for e in results if "same_frame_changed_px" in e]
    report_lines.append(f"foot lock (engine): {len(same)} capture pairs inside one sheet frame, changed pixels around the figure: "
                        + (", ".join(str(e["same_frame_changed_px"]) for e in same) if same else "-"))
    for v in engine_violations:
        report_lines.append("ENGINE VIOLATION " + v)
    report_lines.append(f"sheet consistency: worst drift of a planted foot between two sheet frames: {worst:.1f} px "
                        f"(the engine advances the figure by exactly one stride per frame; what remains is the clip's own foot slide)")
    for v in violations:
        report_lines.append("SHEET " + v)
    text = "\n".join(report_lines) + "\n"
    with open(os.path.join(d, "stride_report.txt"), "w", encoding="utf-8") as f:
        f.write(text)
    with open(os.path.join(d, "stride_report.json"), "w", encoding="utf-8") as f:
        json.dump({"stride_px": stride, "max_drift": args.max_drift, "worst_drift": worst, "sheet_violations": violations,
                   "engine_violations": engine_violations,
                   "frames": [{k: v for k, v in e.items() if not k.startswith("_")} for e in results]}, f, ensure_ascii=False, indent=2)
    print(text)

    # Fixed-floor GIF per label + contact strip with the planted foot marked.
    strip_tiles = []
    for lab, items in tiles.items():
        xs = [e["x_drawn"] for _, e, _ in items]
        scale = items[0][1]["scale"]
        fig_h = int(384 * scale)
        win = (max(0, int(min(xs) - 170 * scale)), max(0, int(min(e["foot_y"] if "foot_y" in e else 1000 for _, e, _ in items) - fig_h - 10)),
               min(1920, int(max(xs) + 170 * scale)), min(1080, int(max(e.get("foot_y", 1000) for _, e, _ in items) + 30)))
        frames_gif = []
        for img, e, prev in items:
            tile = img.crop(win).copy()
            dr = ImageDraw.Draw(tile)
            if prev and "foot_x0" in prev:
                dr.rectangle([prev["foot_x0"] - win[0], prev["foot_y"] - 14 - win[1], prev["foot_x1"] - win[0], prev["foot_y"] - win[1]], outline=(255, 220, 0), width=2)
            if "foot_x0" in e:
                dr.rectangle([e["foot_x0"] - win[0], e["foot_y"] - 14 - win[1], e["foot_x1"] - win[0], e["foot_y"] - win[1]], outline=(255, 40, 40), width=2)
            cap = f"{lab} {e['index']:02d}  frame {e['frame']}  drawn x {e['x_drawn']:.0f}"
            if "drift" in e:
                cap += f"  planted foot moved {e['drift']:+d} px"
            elif e.get("swap"):
                cap += "  foot swap"
            dr.rectangle([0, 0, 8 + 7 * len(cap), 16], fill=(0, 0, 0))
            dr.text((4, 2), cap, fill=(255, 255, 255))
            frames_gif.append(tile)
            strip_tiles.append(tile.resize((tile.width // 2, tile.height // 2)))
        if frames_gif and lab != "hold":
            small = [t.resize((t.width // 2, t.height // 2)) for t in frames_gif]
            small[0].save(os.path.join(d, f"stride_{lab}.gif"), save_all=True, append_images=small[1:], duration=130, loop=0)
    if strip_tiles:
        cols = 4
        tw = max(t.width for t in strip_tiles)
        th = max(t.height for t in strip_tiles)
        rows = (len(strip_tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * th), (30, 30, 30))
        for i, t in enumerate(strip_tiles):
            sheet.paste(t, ((i % cols) * tw, (i // cols) * th))
        sheet.save(os.path.join(d, "stride_strip.jpg"), quality=85)
    sys.exit(1 if engine_violations or (args.strict and violations) else 0)


if __name__ == "__main__":
    main()
