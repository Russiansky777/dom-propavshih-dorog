#!/usr/bin/env python3
"""Even back-and-forth idle sway (Director 17.10: «разворот влево занимал столько же, сколько обратный
вправо»): measures how far the pose moves between consecutive idle frames and writes, per actor and
direction row, which frames to use and where each sits along the motion → `idle_motion` in
game/data/actors/<actor>.json (and switches the idle to playback "pingpong_eased").

    python3 tools/measure_idle.py [actor ...] [--write] [--check] [--period 3.6] [--hold 0.35]

Why: the idle sheets are a 0–20 % window of the Meshy «Idle» clip; the motion accelerates inside the
window (steps between frames ≈ 3 → 9 → 13 → 30 of the metric), so a plain pingpong 0..7,6..1 crawls
at one end and snaps round at the other. Here:
  * step k = mean of the max channel difference (RGBA) over the union of opaque pixels, frame k vs k+1;
  * per row the longest run of ≥ 4 consecutive frames whose steps are even (max/min ≤ 1.35, relaxed in
    0.1 steps only if no run qualifies) is kept — the big end-of-window jumps are dropped;
  * the kept frames get their cumulative path fraction 0..1.
ActorSheet then plays the row as a cosine back-and-forth over that path (period_s, hold_s at both
ends; each moment shows the frame nearest to the eased path position): equal travel time to both
extremes, speed easing to zero at both ends, equal holds.
"""
import argparse
import hashlib
import json
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def compact_json(obj):
    text = json.dumps(obj, ensure_ascii=False, indent=2)
    return re.sub(r"\[\s*(-?[0-9.eE+-]+(?:,\s*-?[0-9.eE+-]+)*)\s*\]",
                  lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]", text)


def steps_of(img, row, n, fw, fh):
    fr = [img[row * fh:(row + 1) * fh, k * fw:(k + 1) * fw].astype(np.int16) for k in range(n)]
    out = []
    for k in range(n - 1):
        a, b = fr[k], fr[k + 1]
        m = (a[..., 3] > 32) | (b[..., 3] > 32)
        out.append(float(np.abs(a - b).max(axis=2)[m].mean()) if m.any() else 0.0)
    return out


def best_run(steps, min_frames=4):
    ratio = 1.35
    while ratio <= 3.0:
        best = None
        for a in range(len(steps) + 1):
            for b in range(a + min_frames - 1, len(steps) + 1):
                seg = steps[a:b]
                if not seg or min(seg) <= 0 or max(seg) / min(seg) > ratio:
                    continue
                key = (b - a, sum(seg))
                if best is None or key > best[0]:
                    best = (key, a, b)
        if best is not None:
            return best[1], best[2], ratio
        ratio = round(ratio + 0.1, 2)
    return 0, len(steps), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("actors", nargs="*")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--period", type=float, default=3.6)
    ap.add_argument("--hold", type=float, default=0.35)
    ap.add_argument("--action", default="", help="action to measure (default: the actor's idle); e.g. talk")
    ap.add_argument("--all-frames", action="store_true", help="keep every frame (a gesture clip: time follows the measured path instead of dropping uneven steps)")
    args = ap.parse_args()
    data_dir = os.path.join(ROOT, "game", "data", "actors")
    actors = args.actors or sorted(f[:-5] for f in os.listdir(data_dir) if f.endswith(".json"))
    code = 0
    for actor in actors:
        path = os.path.join(data_dir, actor + ".json")
        with open(path, encoding="utf-8") as f:
            spec = json.load(f)
        if spec.get("type") == "puppet":
            continue  # bone rig on one picture, no sheet
        sheet_dir = os.path.join(ROOT, "game", spec.get("sheet_dir", f"res://assets/characters/{actor}").replace("res://", ""))
        with open(os.path.join(sheet_dir, spec.get("sprites", "sprites.json")), encoding="utf-8") as f:
            sprites = json.load(f)
        idle_name = args.action or spec.get("idle_action", "idle")
        if idle_name not in sprites["actions"]:
            print(f"{actor}: no action '{idle_name}' — skipped")
            continue
        act = sprites["actions"][idle_name]
        sheet = os.path.join(sheet_dir, act.get("sheet", idle_name + ".png"))
        with open(sheet, "rb") as f:
            md5 = hashlib.md5(f.read()).hexdigest()
        fw, fh, n = int(sprites["frame_w"]), int(sprites["frame_h"]), int(act["frames"])
        img = np.asarray(Image.open(sheet).convert("RGBA"))
        rows = []
        print(f"{actor}/{idle_name}: {os.path.relpath(sheet, ROOT)} ({n} frames, md5 {md5[:10]}…)")
        dirs = int(sprites.get("directions", 8))
        all_steps = [steps_of(img, r, n, fw, fh) for r in range(dirs)]
        # One frame range for every row (turning in place must not change the sway's amplitude):
        # the longest run of ≥ 4 frames whose steps stay even (max/min ≤ 1.6) in ALL rows.
        common = (0, n - 1, n, 0.0) if args.all_frames else None
        for length in ([] if args.all_frames else range(n, 3, -1)):
            for a in range(0, n - length + 1):
                b = a + length - 1
                worst = max(max(st[a:b]) / max(min(st[a:b]), 1e-6) for st in all_steps)
                if worst <= 1.6 and (common is None or (length, -worst) > (common[2], -common[3])):
                    common = (a, b, length, worst)
            if common is not None:
                break
        for r in range(dirs):
            st = all_steps[r]
            if common is not None:
                a, b, ratio = common[0], common[1], (None if args.all_frames else 1.6)
            else:
                a, b, ratio = best_run(st)
            seg = st[a:b]
            cum = np.concatenate([[0.0], np.cumsum(seg)]) / max(sum(seg), 1e-6)
            rows.append({"frames": list(range(a, b + 1)), "path": [round(float(x), 4) for x in cum]})
            print(f"  row {r}: steps {[round(x, 1) for x in st]} → frames {a}..{b} (max/min {max(seg) / min(seg):.2f}, limit {ratio}), path {[round(float(x), 2) for x in cum]}")
        motion = {
            "_comment": f"Ровное качание «{idle_name}» (tools/measure_idle.py): для каждой строки — кадры с ровными шагами движения (рывки клипа отброшены) и их доля пути 0..1. ActorSheet играет их туда-обратно по косинусу (playback pingpong_eased): одинаковое время до обеих крайних поз, замедление до нуля и одинаковая выдержка у обоих краёв. Перемерить после замены листа: python3 tools/measure_idle.py --write" + (f" --action {idle_name}" if args.action else "") + ".",
            "sheet_md5": md5,
            "rows": rows,
        }
        if args.check:
            cur = spec.get("eased_motion", {}).get(idle_name, {})
            stale = cur.get("sheet_md5") != md5 or [r["frames"] for r in cur.get("rows", [])] != [r["frames"] for r in rows]
            print(("FAIL" if stale else "OK") + f" {actor}: eased_motion.{idle_name} " + ("is stale — run with --write" if stale else "matches the sheet"))
            code = max(code, 1 if stale else 0)
        if args.write:
            spec.pop("idle_motion", None)
            spec.setdefault("eased_motion", {})[idle_name] = motion
            acts = spec.setdefault("actions", {})
            idle = acts.setdefault(idle_name, {})
            idle["playback"] = "pingpong_eased"
            idle["period_s"] = args.period
            idle["hold_s"] = args.hold
            with open(path, "w", encoding="utf-8") as f:
                f.write(compact_json(spec) + "\n")
            print(f"  written: {os.path.relpath(path, ROOT)}")
    sys.exit(code)


if __name__ == "__main__":
    main()
